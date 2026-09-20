class User < ApplicationRecord
  include SubscriptionAccess

  has_secure_password
  has_many :sessions, dependent: :destroy

  enum :role, { student: "student", reviewer: "reviewer", admin: "admin" }, prefix: :role

  normalizes :email, with: ->(e) { e.strip.downcase }

  validates :email, presence: true, uniqueness: true
  validates :locale, inclusion: { in: %w[es en] }

  # Salting the token with the current digest invalidates outstanding reset links
  # the moment the password changes — a link that leaked stops working as soon as
  # the account is recovered.
  generates_token_for :password_reset, expires_in: 15.minutes do
    password_salt&.last(10)
  end
end
