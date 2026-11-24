#!/usr/bin/env ruby
# frozen_string_literal: true
require_relative 'field_tool' unless defined?(FieldDefinitions)

module FieldSizeSources
  def self.generate(check = false)
    data=FieldDefinitions.standards
    FieldDefinitions.require_at(data['schemaVersion']==1,'size-standards.schemaVersion','unsupported schema')
    presets=data.fetch('presets'); candidates=data.fetch('auto').fetch('candidates')
    defaults=data.fetch('defaultFieldYears')
    %w[ftc frc].each { |mode| FieldDefinitions.require_at(presets.any? { |p| p['mode']==mode && p['competitionYear']==defaults[mode] },'size-standards.defaults','default season missing') }
    swift = <<~SWIFT
      // BEGIN GENERATED FIELD SIZE CATALOG — edit fields/size-standards.yaml instead.
      enum TagFieldCatalog {
          struct Preset {
              let mode: String
              let year: Int
              let reference: Double
              let game: String
              let requiresKnownID: Bool
              let widths: [Int: Double]
          }
          static let presets: [Preset] = [
      #{presets.map { |p| "        Preset(mode: #{JSON.generate(p['mode'])}, year: #{p['competitionYear']}, reference: #{p['referenceSizeMeters']}, game: #{JSON.generate(p['label'])}, requiresKnownID: #{p['requireKnownID']}, widths: #{p['tagSizes'].empty? ? '[:]' : '['+p['tagSizes'].map { |t| "#{t['id']}: #{t['poseSizeMeters']}" }.join(', ')+']'})," }.join("\n")}
          ]
          static let autoStandards: [(edge: Double, label: String, tolerance: Double)] = [
      #{candidates.map { |c| "        (#{c['poseSizeMeters']}, #{JSON.generate(c['label'])}, #{c['relativeTolerance']})," }.join("\n")}
          ]
          static func defaultYear(mode: String) -> Int { mode == "ftc" ? #{defaults.fetch('ftc')} : (mode == "frc" ? #{defaults.fetch('frc')} : 0) }
          static func referenceWidth(mode: String, year: Int) -> Double? {
              presets.first { $0.mode == mode && $0.year == year }?.reference
          }
          static func width(mode: String, year: Int, tagID: Int?) -> Double? {
              guard let preset = presets.first(where: { $0.mode == mode && $0.year == year }) else { return nil }
              if preset.requiresKnownID { return tagID.flatMap { preset.widths[$0] } }
              return preset.reference
          }
          static func label(mode: String, year: Int) -> String {
              "\\(mode.uppercased()) \\(presets.first { $0.mode == mode && $0.year == year }?.game ?? "") \\(year)"
          }
      }
      // END GENERATED FIELD SIZE CATALOG
    SWIFT
    native=File.join(FieldDefinitions::ROOT,'native/ARCapture/TagDebugMath.swift')
    text=File.read(native)
    pattern=/\/\/ BEGIN GENERATED FIELD SIZE CATALOG.*?\/\/ END GENERATED FIELD SIZE CATALOG\n/m
    if text.match?(pattern)
      revised=text.sub(pattern,swift)
    else
      start=text.index('enum TagFieldCatalog {'); finish=text.index('struct TagDebugSettings:',start)
      raise FieldDefinitions::Invalid,'Cannot locate native size catalog' unless start && finish
      revised=text[0...start]+swift+"\n"+text[finish..-1]
    end
    FieldDefinitions.write_or_check(native,revised,check)
    seasons={}
    %w[ftc frc].each do |mode|
      seasons[mode]=presets.select { |p| p['mode']==mode }.sort_by { |p| [p['competitionYear']==defaults[mode] ? 0 : 1,-p['competitionYear']] }.map do |p|
        sizes=p['tagSizes'].map { |t| t['poseSizeMeters'] }.uniq.sort
        description = if sizes.length>1
          '2- and 5-inch tags (50.8 and 127 mm). Each tag ID uses its season size.'
        else
          "#{format('%.8g',p['referenceSizeMeters']/0.0254)}-inch tags (#{format('%.8g',p['referenceSizeMeters']*1000)} mm)."
        end
        {'year'=>p['competitionYear'],'game'=>p['label'],'referenceSizeMeters'=>p['referenceSizeMeters'],'sizeDescription'=>description}
      end
    end
    reference=presets.find { |p| p['mode']=='frc' && p['competitionYear']==defaults['frc'] }.fetch('referenceSizeMeters')
    quote = lambda { |value| "'" + value.gsub(/[\\'\n\r]/) { |character| {"\\"=>"\\\\", "'"=>"\\'", "\n"=>"\\n", "\r"=>"\\r"}.fetch(character) } + "'" }
    ts = <<~TS
      // Generated from fields/size-standards.yaml. Run generate_sizes.rb after editing YAML.
      export const FRC_REFERENCE_SIZE_METERS = #{reference};
      export const FIELD_SEASONS: Record<
        'ftc' | 'frc',
        {
          year: number;
          game: string;
          referenceSizeMeters: number;
          sizeDescription: string;
        }[]
      > = {
    TS
    seasons.each do |mode, rows|
      ts += "  #{mode}: [\n"
      rows.each do |row|
        ts += "    {\n      year: #{row['year']},\n      game: #{quote.call(row['game'])},\n      referenceSizeMeters: #{row['referenceSizeMeters']},\n"
        desc = "      sizeDescription: #{quote.call(row['sizeDescription'])},"
        ts += desc.length > 80 ? "      sizeDescription:\n        #{quote.call(row['sizeDescription'])},\n" : desc+"\n"
        ts += "    },\n"
      end
      ts += "  ],\n"
    end
    ts += "};\n"
    FieldDefinitions.write_or_check(File.join(FieldDefinitions::ROOT,'FieldSizeCatalog.generated.ts'),ts,check)
    header="/* Generated from fields/size-standards.yaml; do not edit. */\n#ifndef AFSC_SIZE_STANDARDS_GENERATED_H\n#define AFSC_SIZE_STANDARDS_GENERATED_H\n"+
      "#define AFSC_SIZE_STANDARD_COUNT #{candidates.length}\n"+
      "#define AFSC_SIZE_STANDARD_INITIALIZERS {#{candidates.map { |c| "{#{c['poseSizeMeters']}, #{c['relativeTolerance']}}" }.join(', ')}}\n#endif\n"
    FieldDefinitions.write_or_check(File.join(FieldDefinitions::ROOT,'native/SpatialCore/include/afsc_size_standards_generated.h'),header,check)
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    FieldSizeSources.generate(ARGV.include?('--check'))
    puts 'Verified/generated shared size catalog sources.'
  rescue FieldDefinitions::Invalid, KeyError => e
    warn e.message
    exit 1
  end
end
