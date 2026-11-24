#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'psych'
require 'digest'
require 'fileutils'

# One deliberately restricted YAML 1.2 data model; JSON is a supported subset.
# Psych supplies syntax parsing only. Scalar resolution below does not use YAML
# 1.1 booleans, dates, object construction or application-defined tags.
module FieldDefinitions
  ROOT = File.expand_path('../..', __dir__)
  FIELDS = File.join(ROOT, 'fields')
  VERSION = 1
  MAX_BYTES = 2 * 1024 * 1024
  MAX_NODES = 100_000
  class Invalid < StandardError; end

  def self.load_text(text, filename = '<input>')
    raise Invalid, "#{filename}: input exceeds #{MAX_BYTES} bytes" if text.bytesize > MAX_BYTES
    stream = Psych.parse_stream(text)
    raise Invalid, "#{filename}: exactly one YAML/JSON document required" unless stream.children.length == 1
    count = [0]
    visit = lambda do |node, depth|
      count[0] += 1
      raise Invalid, "#{filename}: document too deep or large" if depth > 32 || count[0] > MAX_NODES
      raise Invalid, "#{filename}: explicit tags/anchors are unsupported" if (node.respond_to?(:tag) && node.tag) || (node.respond_to?(:anchor) && node.anchor)
      case node
      when Psych::Nodes::Alias
        raise Invalid, "#{filename}: aliases are unsupported"
      when Psych::Nodes::Mapping
        raise Invalid, "#{filename}: malformed mapping" unless node.children.length.even?
        node.children.each_slice(2).each_with_object({}) do |(key, value), out|
          raise Invalid, "#{filename}: mapping keys must be strings" unless key.is_a?(Psych::Nodes::Scalar)
          raise Invalid, "#{filename}: tagged/anchored keys are unsupported" if key.tag || key.anchor
          name = key.value
          raise Invalid, "#{filename}: duplicate/merge key #{name.inspect}" if out.key?(name) || name == '<<'
          out[name] = visit.call(value, depth + 1)
        end
      when Psych::Nodes::Sequence
        node.children.map { |value| visit.call(value, depth + 1) }
      when Psych::Nodes::Scalar
        if !node.plain
          node.value
        elsif node.value == 'null' || node.value == '~'
          nil
        elsif node.value == 'true' || node.value == 'false'
          node.value == 'true'
        elsif node.value.match?(/\A-?(?:0|[1-9][0-9]*)\z/)
          Integer(node.value)
        elsif node.value.match?(/\A-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?\z/)
          number = Float(node.value)
          raise Invalid, "#{filename}: nonfinite number" unless number.finite?
          number
        elsif node.value.match?(/\A[+-]?\.(?:nan|inf)\z/i)
          raise Invalid, "#{filename}: nonfinite number"
        else
          node.value
        end
      else
        raise Invalid, "#{filename}: unsupported YAML node"
      end
    end
    visit.call(stream.children.first.root, 0)
  rescue Psych::Exception => e
    raise Invalid, "#{filename}: #{e.message}"
  end

  def self.load_file(path)
    load_text(File.read(path, encoding: 'UTF-8'), path)
  end

  def self.scalar?(value)
    !value.is_a?(Hash) && !value.is_a?(Array)
  end

  def self.yaml(value, indent = 0)
    pad = ' ' * indent
    case value
    when Hash
      return "#{pad}{}\n" if value.empty?
      value.keys.sort.map do |key|
        item = value.fetch(key)
        label = "#{pad}#{JSON.generate(key)}:"
        if scalar?(item) || (item.is_a?(Array) && item.all? { |v| scalar?(v) }) || item == {}
          "#{label} #{JSON.generate(item)}\n"
        else
          "#{label}\n#{yaml(item, indent + 2)}"
        end
      end.join
    when Array
      return "#{pad}#{JSON.generate(value)}\n" if value.all? { |v| scalar?(v) }
      value.map { |item| "#{pad}-\n#{yaml(item, indent + 2)}" }.join
    else
      "#{pad}#{JSON.generate(value)}\n"
    end
  end

  def self.sha(bytes)
    Digest::SHA256.hexdigest(bytes)
  end

  def self.require_at(condition, path, message)
    raise Invalid, "#{path}: #{message}" unless condition
  end

  def self.finite_number?(number)
    number.is_a?(Numeric) && number.finite?
  end

  def self.validate_package(data, path = '<package>')
    require_at(data.is_a?(Hash), path, 'package must be a mapping')
    require_at(data['schemaVersion'] == VERSION, "#{path}.schemaVersion", 'unsupported schema version')
    %w[id name program game variant coordinateFrame tagFrame].each do |key|
      require_at(data[key].is_a?(String) && !data[key].empty?, "#{path}.#{key}", 'nonempty string required')
    end
    require_at(%w[frc ftc].include?(data['program']), "#{path}.program", 'unsupported program')
    require_at(data['id'].match?(/\A[a-z0-9-]+\z/), "#{path}.id", 'unsafe package ID')
    %w[seasonStartYear seasonEndYear competitionYear].each do |key|
      require_at(data[key].is_a?(Integer) && (2000..2100).cover?(data[key]), "#{path}.#{key}", 'whole season year required')
    end
    require_at(data['seasonStartYear'] <= data['seasonEndYear'], path, 'season years reversed')
    require_at(data['lengthUnit'] == 'meter' && data['angleUnit'] == 'radian', path, 'meter/radian units required')
    require_at(finite_number?(data['floorElevationMeters']), "#{path}.floorElevationMeters", 'finite field-floor datum required')
    %w[fieldLengthMeters fieldWidthMeters].each do |key|
      require_at(data[key].nil? || (finite_number?(data[key]) && data[key] > 0), "#{path}.#{key}", 'positive dimension or null required')
    end
    source = data['source']
    require_at(source.is_a?(Hash) && source['url'].is_a?(String) && source['sha256'].to_s.match?(/\A[a-f0-9]{64}\z/), "#{path}.source", 'source URL/hash required')
    tags = data['tags']
    require_at(tags.is_a?(Array) && !tags.empty? && tags.length <= 1024, "#{path}.tags", '1–1024 tags required')
    seen = {}
    tags.each_with_index do |tag, index|
      at = "#{path}.tags[#{index}]"
      require_at(tag.is_a?(Hash), at, 'tag must be a mapping')
      id = tag['id']
      require_at(id.is_a?(Integer) && (0..10000).cover?(id), "#{at}.id", 'bounded whole ID required')
      require_at(tag['family'] == 'tag36h11', "#{at}.family", 'unsupported detector family')
      key = [tag['family'], id]
      require_at(!seen[key], at, 'duplicate physical tag identity')
      seen[key] = true
      require_at(finite_number?(tag['poseSizeMeters']) && tag['poseSizeMeters'] > 0 && tag['poseSizeMeters'] <= 5, "#{at}.poseSizeMeters", 'positive physical corner edge required')
      require_at(%w[fixedField movable clusterMember unknown].include?(tag['placement']), "#{at}.placement", 'unsupported placement')
      require_at([true, false].include?(tag['localizationEligible']), "#{at}.localizationEligible", 'boolean required')
      if tag['fieldPose']
        require_at(tag['placement'] == 'fixedField', at, 'only fixed tags may carry a permanent field pose')
        validate_pose(tag['fieldPose'], "#{at}.fieldPose")
        validate_matrix(tag['fieldFromTagColumnMajor'], "#{at}.fieldFromTagColumnMajor")
        derived = matrix(tag['fieldPose']['translation'], tag['fieldPose']['quaternion'])
        require_at(derived.zip(tag['fieldFromTagColumnMajor']).all? { |a, b| (a-b).abs < 1e-8 }, at, 'pose and transform disagree')
      else
        require_at(tag['fieldFromTagColumnMajor'].nil? && !tag['localizationEligible'], at, 'unknown/moving field pose cannot be a localization anchor')
      end
      require_at(!tag['localizationEligible'] || tag['placement'] == 'fixedField', at, 'moving tag cannot be an anchor')
    end
    clusters = data['clusters']
    require_at(clusters.is_a?(Array), "#{path}.clusters", 'array required')
    cluster_names = {}
    member_ids = {}
    clusters.each_with_index do |cluster, index|
      at = "#{path}.clusters[#{index}]"
      name = cluster['id']
      require_at(name.is_a?(String) && !name.empty? && !cluster_names[name], at, 'unique cluster ID required')
      cluster_names[name] = true
      require_at(cluster['fieldPose'].nil? && cluster['localizationEligible'] == false, at, 'moving cluster must not have placeholder global geometry')
      require_at(cluster['members'].is_a?(Array) && cluster['members'].length >= 2, at, 'cluster members required')
      cluster['members'].each do |member|
        id = member['id']
        tag = tags.find { |t| t['id'] == id }
        require_at(tag && tag['clusterId'] == name && tag['placement'] == 'clusterMember' && !member_ids[id], at, 'broken/duplicate cluster membership')
        member_ids[id] = true
        validate_matrix(member['clusterFromTagColumnMajor'], "#{at}.member#{id}")
      end
    end
    tags.select { |t| t['placement'] == 'clusterMember' }.each do |tag|
      require_at(member_ids[tag['id']], path, "member #{tag['id']} has no cluster")
    end
    data
  end

  def self.validate_pose(pose, path)
    require_at(pose.is_a?(Hash), path, 'pose mapping required')
    t, q = pose.values_at('translation', 'quaternion')
    require_at(t.is_a?(Array) && t.length == 3 && t.all? { |n| finite_number?(n) }, path, 'finite XYZ required')
    require_at(q.is_a?(Array) && q.length == 4 && q.all? { |n| finite_number?(n) }, path, 'finite WXYZ required')
    require_at((q.sum { |n| n*n } - 1).abs < 1e-5, path, 'unit quaternion required')
  end

  def self.validate_matrix(m, path)
    require_at(m.is_a?(Array) && m.length == 16 && m.all? { |n| finite_number?(n) }, path, 'finite column-major 4×4 required')
    require_at([3, 7, 11].all? { |i| m[i].abs < 1e-8 } && (m[15]-1).abs < 1e-8, path, 'homogeneous rigid transform required')
    cols = (0..2).map { |c| (0..2).map { |r| m[c*4+r] } }
    (0..2).each { |a| (0..2).each { |b| require_at((cols[a].zip(cols[b]).sum { |x,y| x*y } - (a == b ? 1 : 0)).abs < 1e-6, path, 'orthonormal rotation required') } }
    det = cols[0][0]*(cols[1][1]*cols[2][2]-cols[1][2]*cols[2][1]) - cols[1][0]*(cols[0][1]*cols[2][2]-cols[0][2]*cols[2][1]) + cols[2][0]*(cols[0][1]*cols[1][2]-cols[0][2]*cols[1][1])
    require_at((det-1).abs < 1e-6, path, 'proper rotation required')
  end

  def self.matrix(t, q)
    norm = Math.sqrt(q.sum { |n| n*n })
    w,x,y,z = q.map { |n| n/norm }
    [1-2*y*y-2*z*z, 2*x*y+2*w*z, 2*x*z-2*w*y, 0.0,
     2*x*y-2*w*z, 1-2*x*x-2*z*z, 2*y*z+2*w*x, 0.0,
     2*x*z+2*w*y, 2*y*z-2*w*x, 1-2*x*x-2*y*y, 0.0,
     *t, 1.0]
  end

  def self.quaternion(m)
    r = (0..2).map { |row| (0..2).map { |c| m[c*4+row] } }
    trace = r[0][0]+r[1][1]+r[2][2]
    if trace > 0
      s = Math.sqrt(trace+1)*2
      q = [s/4, (r[2][1]-r[1][2])/s, (r[0][2]-r[2][0])/s, (r[1][0]-r[0][1])/s]
    else
      i = (0..2).max_by { |j| r[j][j] }; j = (i+1)%3; k = (i+2)%3
      s = Math.sqrt(1+r[i][i]-r[j][j]-r[k][k])*2
      v = [0.0]*4; v[0]=(r[k][j]-r[j][k])/s; v[i+1]=s/4; v[j+1]=(r[i][j]+r[j][i])/s; v[k+1]=(r[i][k]+r[k][i])/s
      q=v
    end
    norm=Math.sqrt(q.sum { |n| n*n }); q.map { |n| n/norm }
  end

  def self.multiply(a,b)
    (0...16).map { |i| c=i/4; r=i%4; (0..3).sum { |k| a[k*4+r]*b[c*4+k] } }
  end

  def self.base(id, program, game, first_year, last_year, variant, source)
    {'schemaVersion'=>VERSION, 'id'=>id, 'name'=>"#{program.upcase} #{first_year == last_year ? last_year : "#{first_year}–#{last_year}"} #{game}#{variant == 'standard' ? '' : " · #{variant}"}",
     'program'=>program,'game'=>game,'seasonStartYear'=>first_year,'seasonEndYear'=>last_year,'competitionYear'=>last_year,'variant'=>variant,
     'coordinateFrame'=>program == 'frc' ? 'wpilib-blue-z-up' : 'ftc-centered-z-up', 'tagFrame'=>'detector-x-right-y-down-z-in',
     'lengthUnit'=>'meter','angleUnit'=>'radian','floorElevationMeters'=>0.0,'fieldLengthMeters'=>nil,'fieldWidthMeters'=>nil,
     'source'=>source,'tags'=>[],'clusters'=>[]}
  end

  def self.tag(id,name,size,placement,transform,source_pose=nil,cluster=nil)
    out={'id'=>id,'family'=>'tag36h11','name'=>name,'poseSizeMeters'=>size,'placement'=>placement,
      'localizationEligible'=>placement == 'fixedField','clusterId'=>cluster,
      'fieldPose'=>transform ? {'translation'=>transform.values_at(12,13,14),'quaternion'=>quaternion(transform)} : nil,
      'fieldFromTagColumnMajor'=>transform,'sourcePose'=>source_pose}
    if transform
      out['expectedHeightMeters']=transform[14]
      out['expectedTiltRadians']=Math.asin([transform[10].abs,1.0].min)
    else
      out['expectedHeightMeters']=nil; out['expectedTiltRadians']=nil
    end
    out
  end

  def self.generated
    lock = load_file(File.join(FIELDS,'source-lock.yaml'))
    lock.fetch('files').each do |entry|
      path = File.join(FIELDS,'sources',entry.fetch('file'))
      require_at(sha(File.binread(path))==entry.fetch('sha256'),path,'pinned source hash mismatch')
    end
    packages=[]
    %w[welded andymark].each do |variant|
      filename="2026-rebuilt-#{variant}.json"; bytes=File.binread(File.join(FIELDS,'sources',filename)); src=JSON.parse(bytes)
      source={'url'=>"https://raw.githubusercontent.com/wpilibsuite/allwpilib/v2026.2.2/apriltag/src/main/native/resources/edu/wpi/first/apriltag/#{filename}",'revision'=>'v2026.2.2','sha256'=>sha(bytes),'sourceTagFrame'=>'wpilib-x-out-y-right-z-up','sourceLengthUnit'=>'meter'}
      package=base("frc-2026-rebuilt-#{variant}",'frc','REBUILT',2026,2026,variant,source)
      package['fieldLengthMeters']=src.fetch('field').fetch('length');package['fieldWidthMeters']=src.fetch('field').fetch('width')
      basis=[0.0,1,0,0, 0,0,-1,0, -1,0,0,0, 0,0,0,1]
      package['tags']=src.fetch('tags').map do |t|
        p=t.fetch('pose'); pos=p.fetch('translation').values_at('x','y','z'); q=p.fetch('rotation').fetch('quaternion').values_at('W','X','Y','Z')
        tag(t.fetch('ID'),"Tag #{t.fetch('ID')}",0.1651,'fixedField',multiply(matrix(pos,q),basis),{'translation'=>pos,'quaternion'=>q})
      end
      packages << package
    end
    source_bytes=File.binread(File.join(FIELDS,'sources','AprilTagGameDatabase.java'))
    source={'url'=>'https://repo.maven.apache.org/maven2/org/firstinspires/ftc/Vision/12.0.0/Vision-12.0.0-sources.jar','revision'=>'12.0.0','sha256'=>sha(source_bytes),'artifactSha256'=>'756294f8307da88b85a73c5a804dbc20f65dd60af97534ed3dea8f38e528aba8','sourceTagFrame'=>'detector-x-right-y-down-z-in','sourceLengthUnit'=>'inch','extractedFile'=>'org/firstinspires/ftc/vision/apriltag/AprilTagGameDatabase.java'}
    decode=base('ftc-2025-2026-decode','ftc','DECODE',2025,2026,'standard',source)
    body=source_bytes.split('public static AprilTagLibrary getDecodeTagLibrary()').last.split('public static AprilTagLibrary getBioBuzzTagLibrary()').first
    pattern=/\.addTag\((\d+),\s*"([^"]+)",\s*([\d.]+),\s*(?:new VectorF\(([^)]+)\),\s*DistanceUnit.INCH,\s*new Quaternion\(([^)]+)\)|DistanceUnit.INCH)\)/m
    decode['tags']=body.scan(pattern).map do |id,name,width,position,q|
      pos=position&.split(',')&.map { |v| Float(v.strip.delete_suffix('f')) }
      quat=q&.split(',')&.first(4)&.map { |v| Float(v.strip.delete_suffix('f')) }
      transform=pos ? matrix(pos.map { |v| v*0.0254 },quat) : nil
      tag(Integer(id),name,Float(width)*0.0254,pos ? 'fixedField' : 'movable',transform,pos ? {'translation'=>pos,'quaternion'=>quat} : nil)
    end
    require_at(decode['tags'].map { |t| t['id'] } == (20..24).to_a,'source DECODE','source extraction did not match expected IDs')
    packages << decode
    bio=base('ftc-2026-2027-biobuzz','ftc','BIOBUZZ',2026,2027,'standard',source)
    [[30,'red-scoring','RED SCORING'],[34,'red-audience','RED AUDIENCE'],[38,'blue-audience','BLUE AUDIENCE'],[42,'blue-scoring','BLUE SCORING']].each do |first,id,name|
      members=[-6.5,-2.75,2.75,6.5].each_with_index.map do |x,i|
        m=matrix([x*0.0254,7.1874*0.0254,-5.622*0.0254],[1,0,0,0])
        bio['tags'] << tag(first+i,"#{name} #{i+1}",0.08255,'clusterMember',nil,nil,id)
        {'id'=>first+i,'clusterFromTagColumnMajor'=>m}
      end
      bio['clusters'] << {'id'=>id,'name'=>name,'placement'=>'movable','localizationEligible'=>false,'fieldPose'=>nil,
        'coordinateFrame'=>'detector-cluster-x-right-y-down-z-in','aimingOrigin'=>'cell-opening','members'=>members}
    end
    packages << bio
    packages.each { |p| validate_package(p,p['id']) }
    packages
  end

  def self.standards
    data=load_file(File.join(FIELDS,'size-standards.yaml'))
    require_at(data['schemaVersion']==VERSION && data['family']=='tag36h11','size-standards','unsupported schema/family')
    candidates=data.fetch('auto').fetch('candidates')
    require_at(candidates.is_a?(Array) && !candidates.empty? && candidates.length<=64,'size-standards.auto','bounded candidates required')
    candidates.each_with_index do |c,index|
      require_at(finite_number?(c['poseSizeMeters']) && c['poseSizeMeters']>0 && finite_number?(c['relativeTolerance']) && c['relativeTolerance']>0 && c['relativeTolerance']<=1,"size-standards.auto[#{index}]",'positive finite edge/tolerance required')
    end
    presets=data.fetch('presets'); seen={}
    presets.each do |preset|
      key=[preset['mode'],preset['competitionYear']]
      require_at(%w[ftc frc].include?(preset['mode']) && preset['competitionYear'].is_a?(Integer) && !seen[key], 'size-standards.presets','unique mode/whole year required')
      seen[key]=true
      require_at(finite_number?(preset['referenceSizeMeters']) && preset['referenceSizeMeters']>0, 'size-standards.presets','positive reference size required')
      require_at([true,false].include?(preset['requireKnownID']) && preset['tagSizes'].is_a?(Array), 'size-standards.presets','ID policy required')
      ids={}
      preset['tagSizes'].each do |tag|
        require_at(tag['id'].is_a?(Integer) && !ids[tag['id']] && finite_number?(tag['poseSizeMeters']) && tag['poseSizeMeters']>0, 'size-standards.tagSizes','unique IDs with positive sizes required')
        ids[tag['id']]=true
      end
    end
    %w[ftc frc].each { |mode| require_at(seen[[mode,data.fetch('defaultFieldYears').fetch(mode)]], 'size-standards.defaultFieldYears','default preset missing') }
    data
  end

  def self.write_or_check(path, text, check)
    if check
      require_at(File.file?(path) && File.binread(path)==text.b,path,'generated content differs; run import')
    else
      FileUtils.mkdir_p(File.dirname(path));File.binwrite(path,text)
    end
  end

  def self.import(check=false)
    packages=generated
    packages.each do |package|
      dir=File.join(FIELDS,package['id'])
      write_or_check(File.join(dir,'field.yaml'),yaml(package),check)
      write_or_check(File.join(dir,'manifest.yaml'),yaml(package.reject { |k,_| %w[tags clusters].include?(k) }),check)
      write_or_check(File.join(dir,'tags.yaml'),yaml({'schemaVersion'=>VERSION,'tags'=>package['tags']}),check)
      write_or_check(File.join(dir,'clusters.yaml'),yaml({'schemaVersion'=>VERSION,'clusters'=>package['clusters']}),check)
    end
    write_or_check(File.join(FIELDS,'catalog.yaml'),yaml({'schemaVersion'=>VERSION,'packages'=>packages.map { |p| {'id'=>p['id'],'path'=>"#{p['id']}/field.yaml"} }}),check)
    write_or_check(File.join(FIELDS,'size-standards.yaml'),yaml(standards),check)
    packages
  end

  def self.load_catalog
    index=load_file(File.join(FIELDS,'catalog.yaml'))
    require_at(index['schemaVersion']==VERSION,'catalog.schemaVersion','unsupported version')
    seen={}
    index.fetch('packages').map do |entry|
      require_at(entry['path'].is_a?(String) && entry['path'].match?(/\A[a-z0-9-]+\/field\.yaml\z/),'catalog.path','unsafe package path')
      file=File.join(FIELDS,entry['path']); data=validate_package(load_file(file),file)
      require_at(data['id']==entry['id'] && !seen[data['id']],file,'mismatched/duplicate package ID');seen[data['id']]=true
      [data,File.read(file,encoding:'UTF-8')]
    end
  end

  def self.bundle(output)
    FileUtils.mkdir_p(output)
    packages=load_catalog.map { |data,bytes| data.merge('packageSha256'=>sha(bytes),'yaml'=>bytes) }
    File.write(File.join(output,'catalog.json'),JSON.pretty_generate({'schemaVersion'=>VERSION,'packages'=>packages})+"\n")
    File.write(File.join(output,'size-standards.json'),JSON.pretty_generate(load_file(File.join(FIELDS,'size-standards.yaml')))+"\n")
    FileUtils.cp(File.join(FIELDS,'size-standards.yaml'),output)
    FileUtils.cp(File.join(FIELDS,'NOTICE.md'),output)
    FileUtils.cp(File.join(FIELDS,'sources','WPILib-LICENSE.md'),output)
    packages.each do |p|
      dir=File.join(output,p['id']);FileUtils.mkdir_p(dir);File.binwrite(File.join(dir,'field.yaml'),p['yaml'])
    end
  end

  def self.run(argv)
    command=argv.shift || 'validate'
    case command
    when 'import'
      check=argv.delete('--check')
      import(check)
      require_relative 'generate_sizes'
      FieldSizeSources.generate(check)
      puts 'Validated reproducible field imports and generated size sources.'
    when 'validate'
      if argv.empty?
        count=load_catalog.length;puts "Validated #{count} field packages."
      else
        argv.each { |path| validate_package(load_file(path),path) };puts 'Validated field package.'
      end
    when 'convert'
      path=argv.shift or raise Invalid,'convert requires an input path'
      format=argv.include?('--format') ? argv[argv.index('--format')+1] : 'yaml'
      raise Invalid,'format must be yaml or json' unless %w[yaml json].include?(format)
      data=validate_package(load_file(path),path)
      out=format=='yaml' ? yaml(data) : JSON.pretty_generate(data)+"\n"
      dest=argv.include?('--output') ? argv[argv.index('--output')+1] : nil
      dest ? File.write(dest,out) : $stdout.write(out)
    when 'bundle'
      i=argv.index('--output');raise Invalid,'bundle requires --output directory' unless i && argv[i+1]
      require_relative 'generate_sizes'
      FieldSizeSources.generate(true)
      bundle(argv[i+1]);puts "Bundled field resources at #{argv[i+1]}"
    else
      raise Invalid,'Usage: field_tool.rb [import [--check] | validate [package.yaml|json] | convert input [--format yaml|json] [--output file] | bundle --output directory]'
    end
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    FieldDefinitions.run(ARGV)
  rescue FieldDefinitions::Invalid, KeyError, ArgumentError, Errno::ENOENT => e
    warn e.message
    exit 1
  end
end
