#!/usr/bin/env ruby
# frozen_string_literal: true
require 'minitest/autorun'
require 'tmpdir'
require_relative 'field_tool'

class FieldToolTest < Minitest::Test
  F = FieldDefinitions
  def setup
    @packages = F.generated
  end

  def package(id)
    Marshal.load(Marshal.dump(@packages.find { |p| p['id'] == id }))
  end

  def test_frc_variants_preserve_official_counts_and_dimensions
    welded, am = @packages.first(2)
    assert_equal((1..32).to_a,welded['tags'].map { |t| t['id'] })
    assert_equal([16.541,8.069],welded.values_at('fieldLengthMeters','fieldWidthMeters'))
    assert_equal([16.518,8.043],am.values_at('fieldLengthMeters','fieldWidthMeters'))
    assert_in_delta(11.8779798,welded['tags'][0]['fieldPose']['translation'][0],1e-12)
    refute_equal(welded['tags'][0]['fieldPose'],am['tags'][0]['fieldPose'])
  end

  def test_raw_tag_basis_has_printed_up_and_into_face_normal
    tag = @packages[0]['tags'][0]
    m=tag['fieldFromTagColumnMajor']
    # Official tag1 yaw pi: outward normal is -X. Raw +Z is INTO print (+X).
    assert_in_delta(1,m[8],1e-12)
    assert_in_delta(1,-m[6],1e-12)
    assert_in_delta(0,tag['expectedTiltRadians'],1e-12)
  end

  def test_decode_source_units_and_placeholder_eligibility
    d=@packages[2]
    assert_equal((20..24).to_a,d['tags'].map { |t| t['id'] })
    fixed=d['tags'].select { |t| t['localizationEligible'] }
    assert_equal([20,24],fixed.map { |t| t['id'] })
    assert_equal([-1.48266658,-1.4133194999999998,0.7493],fixed[0]['fieldPose']['translation'])
    assert_in_delta(0.1651,fixed[0]['poseSizeMeters'],1e-12)
    d['tags'][1..3].each { |t| assert_nil(t['fieldPose']);assert_nil(t['fieldFromTagColumnMajor']) }
    assert_nil(d['fieldLengthMeters'])
  end

  def test_biobuzz_member_geometry_is_local_and_moving
    b=@packages[3]
    assert_equal((30..45).to_a,b['tags'].map { |t| t['id'] })
    assert_equal(4,b['clusters'].length)
    b['tags'].each { |t| assert_nil(t['fieldPose']);refute(t['localizationEligible']);assert_in_delta(0.08255,t['poseSizeMeters'],1e-12) }
    m=b['clusters'][0]['members'][0]['clusterFromTagColumnMajor']
    assert_in_delta(-0.1651,m[12],1e-12)
    assert_in_delta(0.18255996,m[13],1e-12)
    assert_in_delta(-0.1427988,m[14],1e-12)
  end

  def test_yaml_json_semantic_and_canonical_round_trip
    @packages.each do |p|
      text=F.yaml(p)
      assert_equal(p,F.load_text(text))
      assert_equal(p,F.load_text(JSON.generate(p)))
      assert_equal(text,F.yaml(F.load_text(text)))
      assert_equal(text,F.yaml(F.load_text(JSON.generate(p))))
    end
  end

  def test_scalar_semantics_preserve_unknown_false_zero_and_season_strings
    obj=F.load_text('"unknown": null' + "\n" + '"enabled": false' + "\n" + '"zero": 0' + "\n" + '"season": "2026–2027"' + "\n")
    assert_nil(obj['unknown']);assert_equal(false,obj['enabled']);assert_equal(0,obj['zero']);assert_equal('2026–2027',obj['season'])
    assert_equal({'yes'=>'on'},F.load_text("yes: on\n")) # YAML 1.2, not 1.1 booleans.
  end

  def test_rejects_duplicate_alias_tags_merge_and_nonfinite
    ["a: 1\na: 2\n",'{"a":1,"a":2}',"a: &x [1]\nb: *x\n",'a: !ruby/object:Foo {}',"<<: {a: 1}\n",'a: .nan','a: 1e999',"? !foo a\n: 1\n"].each do |text|
      assert_raises(F::Invalid,text) { F.load_text(text) }
    end
  end

  def test_rejects_invalid_schema_geometry_and_duplicate_id
    p=package('frc-2026-rebuilt-welded');p['schemaVersion']=99
    assert_raises(F::Invalid) { F.validate_package(p) }
    p=package('frc-2026-rebuilt-welded');p['tags'] << p['tags'][0].dup
    assert_raises(F::Invalid) { F.validate_package(p) }
    p=package('frc-2026-rebuilt-welded');p['tags'][0]['family']='tag16h5'
    assert_raises(F::Invalid) { F.validate_package(p) }
    p=package('frc-2026-rebuilt-welded');p['tags'][0]['poseSizeMeters']=0
    assert_raises(F::Invalid) { F.validate_package(p) }
    p=package('frc-2026-rebuilt-welded');p['tags'][0]['fieldPose']['quaternion']=[0,0,0,0]
    assert_raises(F::Invalid) { F.validate_package(p) }
    p=package('frc-2026-rebuilt-welded');p['tags'][0]['fieldFromTagColumnMajor'][0]=100
    assert_raises(F::Invalid) { F.validate_package(p) }
  end

  def test_rejects_fabricated_dynamic_field_pose_and_broken_members
    p=package('ftc-2026-2027-biobuzz');p['tags'][0]['localizationEligible']=true
    assert_raises(F::Invalid) { F.validate_package(p) }
    p=package('ftc-2026-2027-biobuzz');p['clusters'][0]['members'][0]['id']=999
    assert_raises(F::Invalid) { F.validate_package(p) }
    p=package('ftc-2026-2027-biobuzz');p['tags'][0]['clusterId']='wrong-cluster'
    assert_raises(F::Invalid) { F.validate_package(p) }
  end

  def test_bundle_retains_exact_package_yaml_and_byte_hash
    Dir.mktmpdir('field-bundle') do |out|
      F.bundle(out)
      catalog=JSON.parse(File.read(File.join(out,'catalog.json')))
      assert_equal(4,catalog['packages'].length)
      catalog['packages'].each do |p|
        exact=File.read(File.join(F::FIELDS,p['id'],'field.yaml'),encoding:'UTF-8')
        assert_equal(exact,p['yaml']);assert_equal(F.sha(exact),p['packageSha256'])
        assert_equal(F.load_text(exact),p.reject { |k,_| %w[yaml packageSha256].include?(k) })
      end
    end
  end

  def test_existing_auto_presets_and_mixed_sizes_are_preserved
    s=F.standards
    assert_equal([0.0508,0.08255,0.1016,0.127,0.1524,0.1651],s['auto']['candidates'].map { |c| c['poseSizeMeters'] })
    assert_equal([0.10,0.10,0.10,0.10,0.03,0.03],s['auto']['candidates'].map { |c| c['relativeTolerance'] })
    center=s['presets'].find { |p| p['mode']=='ftc' && p['competitionYear']==2024 }
    assert(center['requireKnownID'])
    assert_equal([7,10],center['tagSizes'].select { |t| t['poseSizeMeters']==0.127 }.map { |t| t['id'] })
    assert_equal(7,s['presets'].length)
  end

  def test_checked_in_files_are_reproducible
    F.import(true)
  end

  def test_ui_swift_and_core_size_sources_match_yaml
    require_relative 'generate_sizes'
    FieldSizeSources.generate(true)
    assert(true)
  end
end
