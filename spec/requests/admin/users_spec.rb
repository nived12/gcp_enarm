require "rails_helper"

RSpec.describe "Admin user lookup", type: :request do
  let(:admin) { create(:user, :admin, email: "admin@example.com") }
  let!(:student) { create(:user, email: "residente.gomez@example.com") }

  before { post session_path, params: { email: admin.email, password: "contrasena-segura" } }

  describe "GET /admin/users" do
    it "finds an account by part of its email" do
      create(:user, email: "otra@example.com")

      get admin_users_path(q: "GOMEZ")

      expect(response.body).to include(student.email)
      expect(response.body).not_to include("otra@example.com")
    end

    it "finds an account by given names and surnames together" do
      named = create(:user, first_name: "María José", last_name: "Pérez López", email: "mj@example.com")

      get admin_users_path(q: "josé pérez")

      expect(response.body).to include(named.email, "María José Pérez López")
      expect(response.body).not_to include(student.email)
    end

    it "treats the search as text, not a pattern" do
      get admin_users_path(q: "%")

      expect(response.body).to include(I18n.t("admin.users.empty.title"))
    end

    it "lists the newest accounts before any search, with granted access noted" do
      student.update!(granted_premium_until: Date.new(2027, 1, 31).end_of_day)

      get admin_users_path

      expect(response.body).to include(student.email, admin.email)
      expect(response.body).to include(
        I18n.t(
          "admin.users.premium_until",
          date: I18n.l(Date.new(2027, 1, 31), format: :long)
        )
      )
    end
  end

  describe "GET /admin/users/:id" do
    it "shows the role, the access window and every access window bought" do
      create(:entitlement, user: student, plan: "three_months", amount: 449)

      get admin_user_path(student)

      expect(response.body).to include(
        student.email, I18n.t("admin.users.roles.student"), I18n.t("admin.users.access.trial"),
        I18n.t("admin.users.entitlements.title"), I18n.t("billing.plans.three_months.name"), "449",
        I18n.t("navigation.admin")
      )
    end

    it "names each kind of access" do
      student.update!(granted_premium_until: 1.month.from_now)
      get admin_user_path(student)
      expect(response.body).to include(I18n.t("admin.users.access.granted"))

      student.update!(granted_premium_until: nil, trial_ends_at: 1.day.ago)
      get admin_user_path(student)
      expect(response.body).to include(
        I18n.t("admin.users.access.free", limit: SubscriptionAccess.free_daily_questions)
      )
    end

    it "does not offer an admin their own role" do
      get admin_user_path(admin)

      expect(response.body).to include(I18n.t("admin.users.own_role"))
      expect(response.body).not_to include('name="user[role]"')
    end
  end

  describe "PATCH /admin/users/:id" do
    it "grants premium through the end of the chosen day and changes the role" do
      patch admin_user_path(student), params: { user: { granted_premium_until: "2027-03-15", role: "reviewer" } }

      expect(student.reload.granted_premium_until).to be_within(1.second).of(Date.new(2027, 3, 15).end_of_day)
      expect(student).to be_role_reviewer
      expect(response).to redirect_to(admin_user_path(student))
      expect(flash[:notice]).to eq(I18n.t("admin.users.saved"))
    end

    it "clears granted premium when the date is emptied" do
      student.update!(granted_premium_until: 1.year.from_now)

      patch admin_user_path(student), params: { user: { granted_premium_until: "", role: "student" } }

      expect(student.reload.granted_premium_until).to be_nil
    end

    it "keeps the role when it is missing or unknown" do
      patch admin_user_path(student), params: { user: { granted_premium_until: "", role: "owner" } }

      expect(student.reload).to be_role_student
    end

    it "refuses a date that does not parse, changing nothing" do
      patch admin_user_path(student), params: { user: { granted_premium_until: "31/02/2027", role: "admin" } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(I18n.t("admin.users.invalid_date"))
      expect(student.reload).to be_role_student
    end

    it "never changes the admin's own role, so the last admin cannot lock themselves out" do
      patch admin_user_path(admin), params: { user: { granted_premium_until: "", role: "student" } }

      expect(admin.reload).to be_role_admin
    end
  end

  describe "POST /admin/users/:id/email_verification" do
    let!(:pending) { create(:user, :unverified, email: "sin.correo@example.com") }

    it "shows an unconfirmed address and lets the admin confirm it, starting the trial" do
      get admin_user_path(pending)
      expect(response.body).to include(I18n.t("admin.users.email.unverified"), I18n.t("admin.users.email.verify"))

      freeze_time
      post admin_user_email_verification_path(pending)

      expect(response).to redirect_to(admin_user_path(pending))
      expect(flash[:notice]).to eq(I18n.t("admin.users.email.done"))
      expect(pending.reload.email_verified_at).to eq(Time.current)
      expect(pending.trial_ends_at).to eq(SubscriptionAccess.trial_days.days.from_now)
      follow_redirect!
      expect(response.body).not_to include(I18n.t("admin.users.email.verify"))
    end

    it "is refused to a reviewer" do
      delete session_path
      reviewer = create(:user, role: "reviewer")
      post session_path, params: { email: reviewer.email, password: "contrasena-segura" }

      post admin_user_email_verification_path(pending)

      expect(pending.reload).not_to be_email_verified
    end
  end
end
