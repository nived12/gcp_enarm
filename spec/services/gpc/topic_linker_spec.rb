require "rails_helper"

RSpec.describe Gpc::TopicLinker do
  def topic(name, aliases = [])
    create(:topic, name: name, slug: name.parameterize, aliases: aliases)
  end

  def link_for(title)
    create(:guideline, title: title)
    described_class.call
    GuidelineTopic.includes(:topic).to_a
  end

  it "fails when the taxonomy has not been seeded" do
    expect(described_class.call.errors.full_messages.first).to include("No hay temas")
  end

  it "links a guideline whose title names the topic" do
    topic("Enfermedad pulmonar obstructiva crónica")

    links = link_for("Diagnóstico y tratamiento de la enfermedad pulmonar obstructiva crónica")

    expect(links.map { |l| l.topic.name }).to eq(["Enfermedad pulmonar obstructiva crónica"])
  end

  # Guideline titles insert words into the middle of a concept. Literal phrase matching
  # missed every title like this one.
  it "links through words the title inserts into the middle of the phrase" do
    topic("Control prenatal", ["cuidados en el embarazo"])

    links = link_for("Atención y cuidados multidisciplinarios en el embarazo")

    expect(links.map { |l| l.topic.name }).to eq(["Control prenatal"])
  end

  it "matches across accents, because the catalog is inconsistent about them" do
    topic("Cetoacidosis diabética")

    expect(link_for("Tratamiento de la cetoacidosis diabetica")).to be_present
  end

  it "matches a plural in the title against a singular topic" do
    topic("Dislipidemia")

    expect(link_for("Diagnóstico y tratamiento de dislipidemias en el adulto")).to be_present
  end

  it "matches a Spanish plural that adds a whole syllable" do
    topic("Infección urinaria")

    expect(link_for("Tratamiento de las infecciones urinarias en el adulto")).to be_present
  end

  # Below five letters a word is an acronym — IAM, TEP, VIH — and chopping a letter off
  # it invents a word that matches nothing.
  it "leaves short words alone rather than singularising an acronym" do
    topic("Infarto agudo de miocardio", ["IAM"])

    expect(link_for("Tratamiento del IAM con elevación del ST")).to be_present
  end

  it "does not match on function words alone" do
    topic("Cáncer de mama")

    expect(link_for("Diagnóstico y tratamiento de la insuficiencia cardiaca")).to be_empty
  end

  it "leaves a topic no guideline names unlinked" do
    topic("Apendicitis aguda")
    topic("Insuficiencia cardiaca")
    link_for("Diagnóstico y tratamiento de la insuficiencia cardiaca aguda")

    expect(Topic.unlinked.pluck(:name)).to eq(["Apendicitis aguda"])
  end

  describe "relevance" do
    it "is highest when the title is the topic and nothing else" do
      topic("Rehabilitación cardiovascular")

      expect(link_for("Rehabilitación cardiovascular").sole.relevance).to eq(1.0)
    end

    it "is low when the topic is one word of a long title" do
      topic("Sepsis y choque séptico", ["sepsis"])

      expect(link_for("Prevención, diagnóstico y tratamiento de la sepsis materna").sole.relevance)
        .to be < described_class::CONFIDENT_RELEVANCE
    end

    it "marks a link confident once it accounts for enough of the title" do
      topic("Endometriosis")
      link_for("Diagnóstico y tratamiento de la endometriosis")

      expect(GuidelineTopic.confident.count).to eq(1)
    end
  end

  it "re-runs without duplicating links" do
    topic("Endometriosis")
    link_for("Diagnóstico y tratamiento de la endometriosis")

    expect { described_class.call }.not_to change(GuidelineTopic, :count)
  end

  it "skips a guideline whose title never extracted" do
    topic("Endometriosis")
    create(:guideline, title: "-")

    expect(described_class.call.payload).to include(links: 0)
  end

  it "reports how much of the corpus and the taxonomy it reached" do
    topic("Endometriosis")

    expect(link_for("Diagnóstico y tratamiento de la endometriosis").size).to eq(1)
    expect(described_class.call.payload).to include(linked_guidelines: 1, linked_topics: 1, guidelines: 1)
  end
end
