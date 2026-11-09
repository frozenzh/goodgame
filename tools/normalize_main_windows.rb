# frozen_string_literal: true

# Main only owns the six native window instances. Their inner layout belongs to
# the individual *Window.tscn scenes, so inherited child overrides are removed.
windows = %w[PlantWindow CottageWindow WorkbenchWindow ShopWindow CodexWindow SettingsWindow]
scene_path = File.expand_path('../scenes/main/Main.tscn', __dir__)
source = File.read(scene_path)
sections = source.split(/(?=^\[node name=|^\[editable path=)/)
removed = 0
cleaned = sections.reject do |section|
  header = section.lines.first.to_s
  parent = header[/\bparent="([^"]+)"/, 1]
  editable = header[/^\[editable path="([^"]+)"/, 1]
  nested_parent = parent && windows.any? { |window| parent == window || parent.start_with?("#{window}/") }
  nested_editable = editable && windows.any? { |window| editable == window || editable.start_with?("#{window}/") }
  inherited_override = header.start_with?('[node name=') && nested_parent && !header.match?(/\b(?:type|instance)=/)
  discard = inherited_override || nested_editable
  removed += 1 if discard
  discard
end.join

if ARGV.include?('--check')
  warn "Main.tscn has #{removed} native-window child overrides" if removed.positive?
  exit(removed.zero? ? 0 : 1)
end

File.write(scene_path, cleaned) if removed.positive?
puts "Removed #{removed} native-window child overrides from Main.tscn"
