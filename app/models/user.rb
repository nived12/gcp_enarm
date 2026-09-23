class User < ApplicationRecord
  include SubscriptionAccess

  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :exams, dependent: :destroy
  has_many :study_days, dependent: :delete_all
  has_many :entitlements, dependent: :destroy
  has_many :question_reports, dependent: :destroy
  has_many :resolved_question_reports, class_name: "QuestionReport", foreign_key: :resolved_by_id,
    inverse_of: :resolved_by, dependent: :nullify
  has_one :study_plan, dependent: :destroy

  TIME_ZONES = TZInfo::Timezone.all_identifiers.to_set.freeze

  # What /account offers, west to east: one per distinct clock a student in Mexico can be
  # on. Since the country dropped daylight saving in 2022 Chihuahua keeps central time and
  # Hermosillo and Mazatlán share an hour; both stay because students look for their city.
  # Sign-up fills the zone from the browser, which may name one not listed here.
  TIME_ZONE_CHOICES = {
    "tijuana" => "America/Tijuana", "hermosillo" => "America/Hermosillo", "mazatlan" => "America/Mazatlan",
    "mexico_city" => "America/Mexico_City", "cancun" => "America/Cancun"
  }.freeze

  enum :role, { student: "student", reviewer: "reviewer", admin: "admin" }, prefix: :role

  normalizes :email, with: ->(e) { e.strip.downcase }
  normalizes :first_name, :last_name, with: ->(value) { value.squish }

  # Given names and surnames are separate so the greeting can use the first alone.
  # Surnames are asked for at sign-up but not required afterwards: accounts created
  # before the split, and some Google profiles, carry only a given name.
  validates :first_name, presence: true, length: { maximum: 100 }
  validates :last_name, length: { maximum: 100 }
  validates :last_name, presence: true, on: :sign_up
  validates :email, presence: true, uniqueness: true
  validates :locale, inclusion: { in: %w[es en] }
  validates :time_zone, inclusion: { in: TIME_ZONES }

  # Salting the token with the current digest invalidates outstanding reset links
  # the moment the password changes — a link that leaked stops working as soon as
  # the account is recovered.
  generates_token_for :password_reset, expires_in: 15.minutes do
    password_salt&.last(10)
  end

  def full_name
    [ first_name, last_name ].compact_blank.join(" ")
  end

  # The day the student is on, in their own time zone.
  def study_date(time = Time.current)
    StudyDay.date_for(time, time_zone)
  end

  def study_day_times(date = study_date)
    StudyDay.time_range(date, time_zone)
  end
end
