class User < ApplicationRecord
  include SubscriptionAccess

  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :exams, dependent: :destroy
  has_many :study_days, dependent: :delete_all
  has_one :study_plan, dependent: :destroy

  enum :role, { student: "student", reviewer: "reviewer", admin: "admin" }, prefix: :role

  normalizes :email, with: ->(e) { e.strip.downcase }

  validates :email, presence: true, uniqueness: true
  validates :locale, inclusion: { in: %w[es en] }
  validates :time_zone, inclusion: { in: TZInfo::Timezone.all_identifiers }

  # Salting the token with the current digest invalidates outstanding reset links
  # the moment the password changes — a link that leaked stops working as soon as
  # the account is recovered.
  generates_token_for :password_reset, expires_in: 15.minutes do
    password_salt&.last(10)
  end

  # The day the student is on, by the study calendar's 4 a.m. boundary.
  def study_date(time = Time.current)
    StudyDay.date_for(time, time_zone)
  end
end
