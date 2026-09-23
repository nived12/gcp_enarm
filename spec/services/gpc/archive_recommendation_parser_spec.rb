require "rails_helper"

RSpec.describe Gpc::ArchiveRecommendationParser do
  # Extracted by pdf-reader from IMSS-031-08 (apendicitis, 2009), four pages of it,
  # including the two sample rows every guideline opens with.
  let(:table) { file_fixture("gpc/archived_evidence_table.txt").read }
  let(:statements) { described_class.call(table).payload }

  def statement(start)
    statements.find { |s| s[:text].start_with?(start) }
  end

  # A table built line by line: marker at column 2, statement at 12, grading at 72.
  # Statements are justified to one right edge, as the PDFs set them.
  def line(marker: "", text: "", grading: "")
    "  #{marker.ljust(8)}  #{justify(text).ljust(52)}        #{grading}".rstrip
  end

  def justify(text, width = 52)
    words = text.split
    return text if words.size < 2 || text.length >= width

    gaps = words.size - 1
    spaces = width - words.sum(&:length)
    words.each_with_index.map do |word, i|
      i < gaps ? word + (" " * ((spaces / gaps) + (i < spaces % gaps ? 1 : 0))) : word
    end.join
  end

  def header
    "            Evidencia / Recomendación                                   Nivel / Grado"
  end

  def parse(*lines) = described_class.call([header, "", *lines].join("\n")).payload

  # Fewer than three E or R letters reads as a template whose markers were images, so a
  # row under test is followed by three ordinary ones.
  def filler
    ["", line(marker: "E", text: "Un estudio de cohorte describió lo mismo.", grading: "III"),
     "", line(marker: "E", text: "Otro estudio de cohorte describió lo mismo.", grading: "III"),
     "", line(marker: "E", text: "Un tercer estudio de cohorte describió lo mismo.", grading: "III")]
  end

  # About forty IMSS guidelines of 2010–2013 set the header and the citations in a bold
  # font that extracts with letters missing, and some of it runs through statements.
  describe "a guideline whose bold glyphs lost letters" do
    def damaged_header
      "            Ev idcia / eRomend c óa i n                               Nivel/ G rado"
    end

    def parse_damaged(*lines) = described_class.call([damaged_header, "", *lines].join("\n")).payload

    it "finds the table by its damaged header and keeps the rows that read cleanly" do
      rows = parse_damaged(
        line(marker: "E", text: "El edema es un signo común en todos los niños.", grading: "III"), *filler
      )

      expect(rows.map { |row| row[:text] }).to include("El edema es un signo común en todos los niños.")
    end

    it "drops a row whose words lost letters, there and only there" do
      garbled = "El OS es la causa más frecuente dá c nr prima o de h u so en adolescentes."
      rows = parse_damaged(line(marker: "E", text: garbled, grading: "III"), *filler)

      expect(rows.map { |row| row[:text] }).not_to include(garbled)
      expect(parse(line(marker: "E", text: garbled, grading: "III"), *filler).map { |row| row[:text] })
        .to include(garbled)
    end

    it "never mistakes a statement line for the damaged header" do
      expect(Gpc::ArchiveTable::Region.table_header?(line(marker: "E", text: "Evitar el uso rutinario.",
                                                          grading: "Nivel D"))).to be(false)
    end
  end

  it "skips the template's sample row even when the scale's name is in quotes" do
    sample = "            Evidencia / Recomendación                                   Nivel / Grado\n" \
             "  E         La valoración del riesgo a través de la escala de “BRADEN”     2++"
    rows = described_class.call([sample, "", header, "", *filler.drop(1)].join("\n")).payload

    expect(rows.map { |row| row[:text] }.join).not_to include("BRADEN")
  end

  describe "a guideline laid out in the usual template" do
    it "reads every row of the table and nothing before it" do
      expect(statements.size).to eq(15)
      expect(statements.map { |s| s[:text] }.join).not_to match(/zanamivir|Braden/)
    end

    it "reads a row whose marker and grades sit in its middle, not on its first line" do
      expect(statement("Se han propuesto 3 criterios")).to include(
        kind: "evidence", grade: "II-b", scale: "Shekelle", citation: "Morishita, 2006",
        label: "II-b (Shekelle,1999) Morishita, 2006"
      )
    end

    it "tells recommendations from evidence by the marker" do
      expect(statement("En mujeres en edad reproductiva")).to include(kind: "recommendation", grade: "C")
    end

    it "files each statement under the numbered headings above it" do
      expect(statement("El cuadro clínico clásico")).to include(
        chapter: "4.2 Diagnostico", heading: "4.2.1.1 Diagnóstico Clínico Y Paraclínico En El Adulto Joven"
      )
    end

    it "keeps list items on lines of their own" do
      expect(statement("De las manifestaciones clínicas")[:text]).to include(
        "son:\n1. Dolor característico ( migración de la región periumbilical al CID o localización inicial en CID\n2."
      )
    end

    it "reads a row broken across a page as one statement, without the page's furniture" do
      text = statement("Aproximadamente 10% de los pacientes")[:text]

      expect(text).to include("40% de los pacientes, sin embargo")
      expect(text).not_to include("Diagnóstico de Apendicitis Aguda")
    end

    it "separates two rows that no blank line separates" do
      expect(statement("En todos los pacientes que presenten SOLO")[:text])
        .to end_with("prueba inmunológica de embarazo.")
      expect(statement("En todos los casos hacer revaloración")).to include(kind: "recommendation", grade: "B")
    end

    it "reads a row whose grade stands on the line above its marker" do
      expect(statement("En adultos jóvenes masculinos")).to include(grade: "I", citation: "Old, 2005")
    end

    it "reads the good-practice tick, which extracts as a private-use character" do
      expect(statement("Ante la duda diagnóstica")).to include(
        kind: "good_practice", grade: "PBP",
        label: "Punto de Buena Práctica"
      )
    end

    it "stops at the chapter after the tables" do
      expect(statements.map { |s| s[:text] }.join).not_to include("inflamación del apéndice")
    end
  end

  describe "a template whose markers were images" do
    let(:table) { file_fixture("gpc/archived_table_without_markers.txt").read }

    it "anchors each row on its grade instead" do
      expect(statements.size).to eq(6)
      expect(statements.first).to include(
        kind: "evidence", grade: "4", scale: "NICE", citation: "Villarreal P. et al 2011", heading: nil
      )
    end

    it "reads a grade written in two words" do
      expect(statement("Las y los pacientes con VIH")).to include(grade: "Baja Calidad", scale: "GRADE")
    end

    it "infers the kind from how the grade is written" do
      rows = parse(
        line(text: "Se recomienda iniciar metformina al diagnóstico.", grading: "A"),
        "",
        line(text: "Se sugiere vigilancia anual del paciente estable.", grading: "PBP"),
        "",
        line(text: "Un ensayo mostró menor mortalidad con metformina.", grading: "1++"),
        "",
        line(text: "Un comité opinó sin asignar un grado conocido.", grading: "Recomendación")
      )

      expect(rows.map { |r| r[:kind] }).to eq(%w[recommendation good_practice evidence])
    end
  end

  describe "grading strips" do
    def grading_of(grading)
      parse(line(marker: "R", text: "Se recomienda realizar ultrasonido abdominal.", grading: grading), *filler).first
    end

    it "reads a scale named as an acronym" do
      expect(grading_of("1++ NICE Hong K, 2021")).to include(grade: "1++", scale: "NICE", citation: "Hong K, 2021")
    end

    it "skips the word that names the grade" do
      expect(grading_of("Nivel D")).to include(grade: "D")
    end

    it "reads a grade written in GRADE's symbols" do
      expect(grading_of("⨁⨁◯◯ GRADE")).to include(grade: "⨁⨁◯◯", scale: "GRADE")
    end

    it "finds a grade that follows its citation" do
      expect(grading_of("Verma, 2013 D")).to include(grade: "D", citation: "Verma, 2013")
      expect(grading_of("NICE Sáez, 2015 2++")).to include(grade: "2++", scale: "NICE")
    end

    it "does not take an author's initial for a grade" do
      expect(grading_of("Smith D, 2010")).to include(grade: nil, citation: "Smith D, 2010")
    end

    it "keeps a row whose grading names nothing it recognises" do
      expect(grading_of("Consenso")).to include(grade: nil, scale: nil, citation: "Consenso")
    end
  end

  describe "where the grading column runs into the statement" do
    it "splits a citation separated from the statement by a single space" do
      row = parse(
        line(marker: "E", text: "La mortalidad fue menor con aspirina."),
        "            #{justify("Se observó en pacientes mayores")} Latenser BA, 2009",
        line(text: "de sesenta años.", grading: "III"),
        *filler
      ).first

      expect(row[:text]).to eq("La mortalidad fue menor con aspirina. Se observó en pacientes mayores de sesenta años.")
      expect(row[:label]).to eq("Latenser BA, 2009 III")
    end

    it "treats a long citation title past the statement column as grading" do
      row = parse(
        line(marker: "R", text: "Se recomienda iniciar tratamiento antirretroviral.", grading: "A"),
        line(text: "Debe hacerse en toda persona con diagnóstico.", grading: "Panel on Treatment of HIV"),
        *filler
      ).first

      expect(row[:text]).not_to include("Panel")
    end

    it "drops a statement the grading column has written over" do
      rows = parse(
        line(marker: "E", text: "La escala mostró buenas propiedades en el", grading: "III"),
        line(text: "servicioLópez M, 2011 de urgencias."),
        "",
        line(marker: "E", text: "Es válida y confiable en niños de uno a cinco años.", grading: "III"),
        "",
        line(marker: "E", text: "Es fácil de aplicar en urgencias pediátricas.", grading: "III")
      )

      expect(rows.map { |r| r[:text] }.join).not_to include("López")
      expect(rows.size).to eq(2)
    end

    it "drops the whole guideline when most of its rows are damaged" do
      rows = parse(
        line(marker: "E", text: "La escala mostró buenas propiedades en el", grading: "III"),
        line(text: "servicioLópez M, 2011 de urgencias."),
        "",
        line(marker: "E", text: "Es válida y confiable en niños de uno a cinco años.", grading: "III")
      )

      expect(rows).to be_empty
    end
  end

  describe "rows the table does not complete" do
    it "keeps a row whose grade block is split from it by a blank line" do
      row = parse(
        line(marker: "E", text: "El tratamiento prolonga la sobrevida.", grading: "4"),
        line(grading: "NICE"),
        "",
        line(grading: "Carter, 2010"),
        *filler
      ).first

      expect(row).to include(grade: "4", scale: "NICE", citation: "Carter, 2010")
    end

    it "skips a heading whose text holds no table rows" do
      rows = parse(
        "        4.1 Generalidades",
        line(text: "Esta sección describe el alcance de la guía."),
        "        4.2 Diagnóstico",
        line(marker: "R", text: "Se recomienda realizar ultrasonido abdominal.", grading: "C"),
        *filler
      )

      expect(rows.map { |r| r[:heading] }.uniq).to eq(["4.2 Diagnóstico"])
    end

    it "labels a good-practice row that carries no grading" do
      row = parse(line(marker: "/R", text: "Explicar el procedimiento a la familia."), *filler).first

      expect(row).to include(kind: "good_practice", grade: "PBP", label: "PBP")
    end

    it "drops a graded row with no grading and a marker with no statement" do
      rows = parse(
        line(marker: "R", text: "Se recomienda algo que nadie gradó."),
        "", line(marker: "R", grading: "A"),
        *filler
      )

      expect(rows.map { |r| r[:text] }).to eq(
        ["Un estudio de cohorte describió lo mismo.", "Otro estudio de cohorte describió lo mismo.",
         "Un tercer estudio de cohorte describió lo mismo."]
      )
    end
  end

  # Some templates do not justify, so no column is where most lines end.
  it "reads a table whose statements are set ragged" do
    ragged = ->(marker, text, grading = "") { "  #{marker.ljust(8)}  #{text}".ljust(74) + grading }
    rows = parse(
      ragged.call("R", "Se recomienda iniciar metformina al diagnóstico", "A"),
      ragged.call("", "en todo adulto con diabetes tipo 2."),
      "", "  E",
      ragged.call("", "Un ensayo mostró menor mortalidad en el grupo tratado.", "1++"),
      "", ragged.call("E", "Un estudio de cohorte describió lo mismo en mujeres.", "2+"),
      "", ragged.call("R", "Se sugiere vigilar la función renal cada año.", "B")
    )

    expect(rows.map { |r| r[:grade] }).to eq(%w[A 1++ 2+ B])
    expect(rows.first[:text])
      .to eq("Se recomienda iniciar metformina al diagnóstico en todo adulto con diabetes tipo 2.")
  end

  describe "what extraction mangles" do
    it "reads a lone Wingdings tick in the marker column as good practice" do
      row = parse(line(marker: "\u{F0FC}", text: "Explicar el procedimiento a la familia."), *filler).first

      expect(row).to include(kind: "good_practice", text: "Explicar el procedimiento a la familia.")
    end

    it "drops a marker icon it cannot name instead of reading it as text" do
      rows = parse(
        line(text: "Se sugiere vigilancia anual del paciente estable.", grading: "PBP"),
        line(marker: "\u{F0E0}", text: "Sin cambios en el tratamiento."),
        "",
        line(text: "Un ensayo mostró menor mortalidad con metformina.", grading: "1++")
      )

      expect(rows.first[:text])
        .to eq("Se sugiere vigilancia anual del paciente estable. Sin cambios en el tratamiento.")
    end

    it "keeps a list bullet that sits right against its item" do
      row = parse(
        line(marker: "R", text: "La consulta prenatal debe incluir:", grading: "A"),
        "          \u{F0B7}  Medir altura y peso",
        "          \u{F0B7}  Solicitar biometría hemática",
        *filler
      ).first

      expect(row[:text])
        .to eq("La consulta prenatal debe incluir:\n• Medir altura y peso\n• Solicitar biometría hemática")
    end

    # Only the letters decide: a template can draw E and R as images and still print
    # the tick as a glyph.
    it "reads by grade when only the good-practice ticks came through as text" do
      rows = parse(
        line(text: "Se recomienda iniciar metformina al diagnóstico.", grading: "A"),
        "", line(marker: "\u{F0FC}", text: "Explicar el procedimiento a la familia.", grading: "PBP"),
        "", line(marker: "\u{F0FC}", text: "Revisar la técnica de inyección en cada cita.", grading: "PBP"),
        "", line(marker: "\u{F0FC}", text: "Registrar el peso en cada consulta de control.", grading: "PBP")
      )

      expect(rows.map { |r| r[:kind] }).to eq(%w[recommendation good_practice good_practice good_practice])
    end

    it "drops a statement whose line lost its spaces" do
      rows = parse(
        line(marker: "R", text: "Larehidrataciónvíaintravenosa serecomiendaenpacientes", grading: "A"),
        *filler
      )

      expect(rows.map { |r| r[:text] }.join).not_to include("Larehidratación")
      expect(rows.size).to eq(3)
    end
  end

  describe "text it cannot read" do
    it "returns nothing for a guideline with no evidence table" do
      expect(described_class.call("Introducción\n\nEsta guía no tiene tablas.").payload).to eq([])
    end

    it "returns nothing for a table with neither markers nor text" do
      expect(described_class.call("#{header}\n\n").payload).to eq([])
    end
  end
end
