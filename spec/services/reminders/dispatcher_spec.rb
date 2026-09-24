require "rails_helper"

RSpec.describe Reminders::Dispatcher do
  let(:user) { create(:user, time_zone: "America/Mexico_City") }
  let(:date) { Date.new(2026, 10, 6) }
  let(:plan) { create(:study_plan, user: user, starts_on: date - 30, exam_date: date + 60) }
  let!(:plan_day) { create(:study_plan_day, study_plan: plan, date: date, kind: "review") }
  let!(:preference) { create(:reminder_preference, user: user, study_days: true, by_email: true) }

  def at(hour, minute = 0)
    ActiveSupport::TimeZone[user.time_zone].local(date.year, date.month, date.day, hour, minute)
  end

  def dispatch(time)
    described_class.call(user: user.reload, now: time).payload
  end

  def studied(on)
    StudyDay.create!(user: user, date: on, questions_answered: StudyDay::MINIMUM_QUESTIONS)
  end

  describe "the study-day reminder" do
    it "goes out by email in the hour after the chosen time, and only then" do
      expect(dispatch(at(7, 59))).to eq([])
      expect { expect(dispatch(at(8, 0))).to eq(["study_day"]) }
        .to have_enqueued_mail(RemindersMailer, :reminder)
      expect(ReminderDelivery.sole).to have_attributes(local_date: date, kind: "study_day", channels: ["email"])
    end

    it "is sent once however many runs fall in the window" do
      expect { 4.times { |quarter| dispatch(at(8, quarter * 15)) } }
        .to have_enqueued_mail(RemindersMailer, :reminder).exactly(:once)
    end

    it "does not fire late: the window closes an hour after the chosen time" do
      expect(dispatch(at(9, 0))).to eq([])
    end

    it "is skipped once the day already counts" do
      studied(date)

      expect(dispatch(at(8))).to eq([])
    end

    it "is skipped once the plan's day is marked done" do
      plan_day.update!(completed_at: Time.current)

      expect(dispatch(at(8))).to eq([])
    end

    it "stays quiet on rest days, catch-up days and without a plan" do
      expect(dispatch(at(8).tomorrow)).to eq([])

      plan_day.update!(kind: "catch_up")
      expect(dispatch(at(8))).to eq([])

      plan.destroy!
      expect(dispatch(at(8))).to eq([])
    end

    it "sends nothing, and claims nothing, with no channel to send on" do
      preference.update!(by_email: false)

      expect(dispatch(at(8))).to eq([])
      expect(ReminderDelivery.count).to eq(0)
    end
  end

  describe "the streak nudge" do
    before do
      preference.update!(study_days: false, streak_at_risk: true)
      studied(date - 1)
    end

    it "goes out at 20:00 when a streak is running and today does not count yet" do
      expect(dispatch(at(19, 59))).to eq([])
      expect(dispatch(at(20))).to eq(["streak_at_risk"])
    end

    it "is not sent once today counts" do
      studied(date)

      expect(dispatch(at(20))).to eq([])
    end

    it "is not sent without a streak to lose" do
      StudyDay.delete_all

      expect(dispatch(at(20))).to eq([])
    end

    it "never fires on a day the study reminder covers" do
      preference.update!(study_days: true)

      expect(dispatch(at(20))).to eq([])
    end

    it "shares the one daily message with the study reminder" do
      preference.update!(study_days: true)
      expect(dispatch(at(8))).to eq(["study_day"])

      preference.update!(study_days: false)
      expect(dispatch(at(20))).to eq([])
    end
  end

  describe "the exam countdown" do
    before { preference.update!(study_days: false, exam_countdown: true) }

    it "goes out 30, 7 and 1 days before the exam and on no other day" do
      sent = (date..date + 59).select { |day| dispatch(at(8) + (day - date).days).include?("exam_countdown") }

      expect(sent.map { |day| (plan.exam_date - day).to_i }).to eq([30, 7, 1])
    end

    it "joins the study reminder in one message when both are due together" do
      preference.update!(study_days: true)
      plan.update!(exam_date: date + 7)

      expect { expect(dispatch(at(8))).to eq(%w[exam_countdown study_day]) }
        .to have_enqueued_mail(RemindersMailer, :reminder).exactly(:once)
    end

    it "needs a plan to know the exam date" do
      plan.destroy!

      expect(dispatch(at(8))).to eq([])
    end
  end

  describe "push", :web_push do
    let!(:phone) { create(:push_subscription, user: user) }
    let!(:laptop) { create(:push_subscription, user: user) }

    before { preference.update!(by_email: false) }

    it "notifies every subscribed device until the student's midnight" do
      expect { dispatch(at(8)) }.to have_enqueued_job(PushNotificationJob).exactly(:twice)

      subscription, payload, ttl = enqueued_jobs.first[:args]
      expect(GlobalID::Locator.locate(subscription["_aj_globalid"])).to eq(phone)
      expect(JSON.parse(payload)).to include(
        "title" => I18n.t("reminders.message.study_day.title"), "path" => "/study_plan/days/2026-10-06"
      )
      expect(ttl).to eq(16.hours.to_i)
      expect(ReminderDelivery.sole.channels).to eq(["push"])
    end

    it "uses both channels when both are on" do
      preference.update!(by_email: true)

      expect { dispatch(at(8)) }.to have_enqueued_mail(RemindersMailer, :reminder)
      expect(ReminderDelivery.sole.channels).to eq(%w[push email])
    end

    it "is not a channel while Web Push is unconfigured" do
      ENV.delete("VAPID_PUBLIC_KEY")

      expect(dispatch(at(8))).to eq([])
    end
  end
end
