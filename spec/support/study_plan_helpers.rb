# A syllabus shaped like the real one, small enough to reason about: the four troncales
# in their reading positions, one transversal setting, and one specialty with no topics.
module StudyPlanHelpers
  SYLLABUS = [
    ["Medicina Interna", "medicina-interna", 1, "core", "indigo"],
    ["Pediatría", "pediatria", 2, "core", "green"],
    ["Gineco-Obstetricia", "gineco-obstetricia", 3, "core", "magenta"],
    ["Cirugía General", "cirugia-general", 4, "core", "amber"],
    ["Urgencias", "urgencias", 6, "cross_cutting", "red"]
  ].freeze

  # Eight topics a specialty, in two branches whose positions run against their ids.
  def create_syllabus(topics_per_branch: 4)
    create(:specialty, name: "Medicina Familiar", slug: "medicina-familiar", position: 7, kind: "cross_cutting")
    SYLLABUS.to_h do |name, slug, position, kind, color|
      specialty = create(:specialty, name: name, slug: slug, position: position, kind: kind, color_token: color)
      second = create(:branch, specialty: specialty, name: "#{name} B", position: 2)
      first = create(:branch, specialty: specialty, name: "#{name} A", position: 1)
      topics = [first, second].flat_map do |branch|
        Array.new(topics_per_branch) do |i|
          create(:topic, branch: branch, name: "#{branch.name} #{i + 1}", position: i + 1)
        end
      end
      [slug, topics]
    end
  end
end

RSpec.configure { |config| config.include StudyPlanHelpers }
