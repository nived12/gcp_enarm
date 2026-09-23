# Reads where a case happens from its vignette, for the cases written before the prompt
# asked the model to say so. Deterministic and local: phrases, not a model call.
#
# Generated stems state their setting in the opening sentence or two ("Acude a consulta
# de medicina familiar…", "…es traído al servicio de urgencias…", "Durante una jornada
# de salud pública…"), in Spanish or in English, so a phrase list reads nearly all of
# them. Two rules settle a stem that names more than one:
#
# - The first phrase wins. The setting is where the story opens; a later mention is
#   usually something that happens next ("se envía a urgencias") or history.
# - A place is weaker than an activity. A centro de salud hosts both the family
#   doctor's consult and the vaccination campaign, so "acude a un centro de salud como
#   parte de un programa de vigilancia epidemiológica" is public health, and the centro
#   de salud decides only when nothing else is named.
#
# Anything else — an ICU, a labour ward, a stem that names no place — stays unknown
# rather than being guessed into one of the three.
module Questions
  class SettingClassifier < ApplicationService
    Marker = Data.define(:code, :pattern, :strong)

    # Matched against the stem lower-cased and stripped of accents, so "Pública",
    # "publica" and "PÚBLICA" are one phrase.
    #
    # A dermatologist's "brote de psoriasis" is a flare, not an outbreak, and "un problema
    # de salud pública" is a statement about a disease, not a place.
    PUBLIC_HEALTH = /
      (?<!problema\sde\s)salud\spublica | public\shealth
      | \bjornadas?\s(?:\w+\s){0,3}?(?:salud|vigilancia|tamizaje|vacunacion|prevencion|deteccion|comunitari)
      | \bcampanas?\s(?:\w+\s){0,2}?de\s(?:salud|vacunacion|prevencion|deteccion|tamizaje|vigilancia|educacion)
      | vigilancia\sepidemiologica | epidemiological\ssurveillance | cerco\sepidemiologico
      | \bbrigadas?\b | \bcentro\scomunitario | contact\stracing | estudio\sde\scontactos
      | \bbrote\s(?:epidemico|epidemiologico|comunitario) | \boutbreak
      | \b(?:durante|ante|por)\s(?:un|el)\sbrote\sde\s
        (?!lesiones|psoria|dermatitis|acne|urticaria|esclerosis|colitis|crohn|eccema|rosacea|lupus|artritis)
      | tamizaje\s(?:comunitario|masivo|poblacional|escolar) | community\s(?:screening|outreach)
      | programa\s(?:comunitario|nacional|de\ssalud|de\svigilancia|de\stamizaje|de\sprevencion|de\svacunacion)
      | (?:vaccination|immunization|screening)\s(?:campaign|drive|program|fair) | health\sfair
      | community\shealth\s(?:program|campaign|worker)
    /x

    # "Urgencias" in the plural is the service; "de urgencia" in the singular is how soon
    # a surgeon operates, which says nothing about where the patient was seen.
    EMERGENCY = /
      \burgencias\b | servicio\sde\semergencias | sala\sde\s(?:choque|reanimacion) | area\sde\schoque
      | emergency\s(?:department|room|service|unit|ward) | trauma\sbay | resuscitation\s(?:room|bay)
    /x

    FAMILY_MEDICINE = /
      medicina\sfamiliar | medico\sfamiliar | primer\snivel | consultorio | \bumf\b
      | family\s(?:medicine|practice|physician|doctor) | primary\s(?:health\s)?care | general\spracti(?:ce|tioner)
    /x

    # Places, not activities: the family doctor's consult and the vaccination campaign
    # both happen in a centro de salud.
    HEALTH_CENTRE = /centro\sde\ssalud | unidad\sde\ssalud | health\s(?:center|centre|clinic)/x

    # A place that is none of the three. Named first, it keeps a later phrase from
    # deciding: the pilot's case 148 is a ventilated patient in intensive care, and
    # "medidas de vigilancia epidemiológica" further on is about preventing pneumonia on
    # the ward, not a public-health setting. It can only ever leave a case unknown.
    HOSPITAL = /
      cuidados\sintensivos | terapia\sintensiva | intensive\scare | labor\sand\sdelivery | admitted\sto\sthe
      | sala\sde\shospitalizacion
    /x

    MARKERS = [
      Marker.new("public_health", PUBLIC_HEALTH, true),
      Marker.new("emergency", EMERGENCY, true),
      Marker.new("family_medicine", FAMILY_MEDICINE, true),
      Marker.new(nil, HOSPITAL, true),
      Marker.new("family_medicine", HEALTH_CENTRE, false)
    ].freeze

    # A patient sent from the family doctor to urgencias is seen in urgencias. The phrase
    # naming where they were sent from is blanked before matching, so it cannot win by
    # coming first.
    REFERRALS = /
      (?:enviad|referid|derivad|trasladad|canalizad)[oa]s?\s(?:\w+\s){0,3}?(?:por|de|desde)\s
      (?:su\s|el\s|la\s|una?\s)?(?:medico\sfamiliar|unidad\sde\smedicina\sfamiliar|medicina\sfamiliar|
      centro\sde\ssalud|primer\snivel|consultorio)
      |referred\s(?:by|from)\s(?:his\s|her\s|their\s|a\s|the\s)?(?:family\s(?:physician|doctor)|primary\scare)
    /x

    # The code of the setting a stem opens in, or nil when it names none of the three.
    def self.code_for(stem)
      text = I18n.transliterate(stem.to_s).downcase.gsub(REFERRALS) { |phrase| " " * phrase.length }
      MARKERS.filter_map { |marker| (at = text.index(marker.pattern)) && [marker.strong ? 0 : 1, at, marker] }
             .min_by { |strength, at, _marker| [strength, at] }&.last&.code
    end

    # Only cases whose setting is unknown: one the model named, or a reviewer corrected,
    # is never overwritten by a phrase list.
    def initialize(cases: ClinicalCase.all, dry_run: false)
      super()
      @cases = cases
      @dry_run = dry_run
    end

    def call
      classified = Hash.new(0)
      unclassified = []

      cases.where(setting_id: nil).find_each do |kase|
        setting = Specialty.for_setting_code(self.class.code_for(kase.stem))
        next unclassified << kase.id if setting.nil?

        kase.update!(setting: setting) unless dry_run
        classified[setting.slug] += 1
      end

      success(classified: classified, unclassified: unclassified)
    end

    private

    attr_reader :cases, :dry_run
  end
end
