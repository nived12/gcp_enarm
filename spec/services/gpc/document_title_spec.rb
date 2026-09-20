require "rails_helper"

RSpec.describe Gpc::DocumentTitle do
  def title_for(*lines) = described_class.call(lines.join("\n")).payload

  # The template prints the catalog key and then the running header, on every page.
  def page(title, key: "GPC-IMSS-051-18")
    ["Catálogo Maestro de Guías de Práctica Clínica: #{key}", title, "Publicado por CENETEC"]
  end

  it "takes the line that follows the catalog key" do
    expect(title_for(*page("Tratamiento quirúrgico de la obesidad en el adulto")))
      .to eq("Tratamiento quirúrgico de la obesidad en el adulto")
  end

  # The legal boilerplate says "Catálogo Maestro" in running prose, which is how an
  # earlier version of this ended up naming every guideline after a government programme.
  it "ignores the phrase where it appears in prose rather than beside a key" do
    text = [
      "que integran el Catálogo Maestro de Guías de Práctica Clínica, el cual se instrumenta",
      "a través del Programa de Acción Específico: Evaluación y Gestión de Tecnologías",
      *page("Diagnóstico y tratamiento de la enfermedad pulmonar obstructiva crónica")
    ]

    expect(title_for(*text)).to eq("Diagnóstico y tratamiento de la enfermedad pulmonar obstructiva crónica")
  end

  it "falls back to the most repeated line when no key survived the scan" do
    text = ["Diagnóstico y tratamiento de la diabetes gestacional"] * 4 + ["Página 12", "Otra cosa"]

    expect(title_for(*text)).to eq("Diagnóstico y tratamiento de la diabetes gestacional")
  end

  it "prefers the header that repeats over one that appears once" do
    text = page("Atención y cuidados multidisciplinarios en el embarazo") * 3 +
           page("Un encabezado que sólo aparece una vez en todo el documento")

    expect(title_for(*text)).to eq("Atención y cuidados multidisciplinarios en el embarazo")
  end

  describe "scans that lost their spacing" do
    it "restores a title run together in title case" do
      expect(title_for(*page("RehabilitaciónDelPacienteAdultoAmputadoDeExtremidadInferior")))
        .to eq("Rehabilitación Del Paciente Adulto Amputado De Extremidad Inferior")
    end

    # Nothing puts the words back in one of these, so it is refused and the guideline
    # keeps its catalog key as its name.
    it "refuses a title spaced letter by letter rather than inventing one" do
      expect(title_for(*page("A T E N C I Ó N I N T E G R A L E N N E U R O R E H A B"))).to be_nil
    end
  end

  describe "lines that are not the title" do
    it "rejects the address block, the publisher and the bibliography" do
      text = ["Av. Paseo de la Reforma No. 450, piso 13, Colonia Juárez"] * 5 +
             ["Publicado por CENETEC, Copyright © 2018"] * 5 +
             ["Shoulder deformity . Journal of Pediatric Orthopaedics, doi:10.1000"] * 5 +
             ["DIRECTORIO SECTORIAL DIRECTORIO DEL CENTRO NACIONAL"] * 5 +
             page("Diagnóstico y tratamiento del sobrepeso y obesidad exógena")

      expect(title_for(*text)).to eq("Diagnóstico y tratamiento del sobrepeso y obesidad exógena")
    end

    # When pdf-reader cannot recover a guideline's running header, the most-repeated
    # line is whatever else recurs — and in these documents that is a search strategy, a
    # bibliography entry or a metadata table. Each of these named a real guideline until
    # it was refused. A wrong title is worse than none: the student reads nonsense, and
    # the topic linker matches the nonsense.
    {
      "a search strategy" => "52. #49 (#6 OR #17 OR #27 OR #32) AND #50 (#7 OR #18 OR #28)",
      "a bibliography entry" => "20. Goble DJ, Bilateral facilitation of upper limb movements in children",
      "a professionals table row" => "Profesionales Reumatología, Medicina Interna, Medicina Familiar",
      "a numbered staff list" => "1.24.Médicoen Rehabilitación 1.46.Médico Psiquiatra dos",
      "a bulleted clinical list" => "• Que no cumpla ningún criterio • Diabetes Mellitus • IAM SEST",
      "a table cell" => "Recién nacido / lactante prematuro tardío",
      "a quoted search term" => "“gastroesophageal reflux” in infants and children under",
      "a publication date line" => "Fecha de publicación de la actualización: 2 de diciembre de 2015"
    }.each do |description, line|
      it "refuses #{description}" do
        expect(title_for(*page(line))).to be_nil
      end
    end

    it "refuses a single long word, which is never a title" do
      expect(title_for(*page("Electroencefalografía"))).to be_nil
    end

    it "refuses a line that is mostly not letters" do
      expect(title_for(*page("2012/01/01 2019/02/15 1000 2000 3000 4000 5000"))).to be_nil
    end

    it "rejects a line too short to be a title" do
      expect(title_for(*page("Objetivo"))).to be_nil
    end

    it "fails when nothing in the document reads as a title" do
      response = described_class.call("Página 3\nCENETEC\n")

      expect(response).not_to be_success
      expect(response.errors.full_messages.first).to include("título legible")
    end
  end
end
