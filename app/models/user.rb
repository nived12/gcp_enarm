class User < ApplicationRecord
  include SubscriptionAccess

  has_secure_password
  has_many :sessions, dependent: :destroy

  enum :role, { student: "student", reviewer: "reviewer", admin: "admin" }, prefix: :role

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true
  validates :locale, inclusion: { in: %w[es en] }
end
