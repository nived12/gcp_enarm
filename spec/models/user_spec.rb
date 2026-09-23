require "rails_helper"

RSpec.describe User do
  describe "validations" do
    it "requires an email address" do
      user = build(:user, email: nil)

      expect(user).not_to be_valid
      expect(user.errors).to be_of_kind(:email, :blank)
    end

    it "rejects a duplicate email address instead of leaving it to the unique index" do
      create(:user, email: "gabriela@example.com")
      duplicate = build(:user, email: "gabriela@example.com")

      expect(duplicate).not_to be_valid
      expect(duplicate.errors).to be_of_kind(:email, :taken)
    end

    it "rejects a locale the UI has no translations for" do
      expect(build(:user, locale: "fr")).not_to be_valid
    end

    it "requires a given name, and surnames only when signing up" do
      expect(build(:user, first_name: " ")).not_to be_valid
      expect(build(:user, last_name: nil)).to be_valid
      expect(build(:user, last_name: nil).valid?(:sign_up)).to be(false)
      expect(build(:user, first_name: "a" * 101)).not_to be_valid
      expect(build(:user, last_name: "a" * 101)).not_to be_valid
    end
  end

  describe "#full_name" do
    it "joins given names and surnames, and stands alone without surnames" do
      expect(build(:user, first_name: "María José", last_name: "Pérez López").full_name).to eq("María José Pérez López")
      expect(build(:user, first_name: "Gabriela", last_name: nil).full_name).to eq("Gabriela")
    end
  end

  describe "normalization" do
    it "downcases and strips the email address" do
      user = create(:user, email: "  Gabriela@Example.COM ")

      expect(user.email).to eq("gabriela@example.com")
    end

    it "collapses stray whitespace in names" do
      user = create(:user, first_name: "  María   José ", last_name: " Pérez  López ")

      expect([ user.first_name, user.last_name ]).to eq([ "María José", "Pérez López" ])
    end
  end

  describe "roles" do
    it "exposes prefixed predicates for each role" do
      expect(create(:user)).to be_role_student
      expect(create(:user, :admin)).to be_role_admin
    end
  end

  describe "password reset tokens" do
    let(:user) { create(:user, password: "contrasena-segura") }

    it "round-trips a freshly generated token" do
      token = user.password_reset_token

      expect(User.find_by_password_reset_token!(token)).to eq(user)
    end

    it "invalidates outstanding tokens once the password changes" do
      token = user.password_reset_token
      user.update!(password: "otra-contrasena", password_confirmation: "otra-contrasena")

      expect {
        User.find_by_password_reset_token!(token)
      }.to raise_error(ActiveSupport::MessageVerifier::InvalidSignature)
    end

    it "still generates a token for a record that has no password digest yet" do
      expect { User.new.password_reset_token }.not_to raise_error
    end

    it "expires the token after 15 minutes" do
      token = user.password_reset_token

      travel 16.minutes do
        expect {
          User.find_by_password_reset_token!(token)
        }.to raise_error(ActiveSupport::MessageVerifier::InvalidSignature)
      end
    end
  end
end
