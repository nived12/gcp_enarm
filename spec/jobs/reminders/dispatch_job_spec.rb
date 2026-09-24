require "rails_helper"

# The run every 15 minutes: one UTC instant, many students, each on their own clock.
RSpec.describe Reminders::DispatchJob do
  let(:date) { Date.new(2026, 10, 6) }

  def student(time_zone, **attributes)
    create(:user, time_zone: time_zone, **attributes).tap do |user|
      plan = create(:study_plan, user: user, starts_on: date - 30, exam_date: date + 90)
      (0..40).each { |offset| create(:study_plan_day, study_plan: plan, date: date + offset, kind: "review") }
      create(:reminder_preference, user: user, study_days: true, by_email: true)
    end
  end

  def run_at(utc)
    described_class.perform_now(now: utc)
    ReminderDelivery.pluck(:user_id, :local_date)
  end

  it "reaches each student at 08:00 on their own clock" do
    tijuana = student("America/Tijuana")
    mexico_city = student("America/Mexico_City")
    cancun = student("America/Cancun")

    # October, before the US clocks change: Cancún is UTC-5, the centre UTC-6 and
    # Tijuana, which follows California, UTC-7.
    expect(run_at(Time.utc(2026, 10, 6, 13, 0))).to eq([[cancun.id, date]])
    expect(run_at(Time.utc(2026, 10, 6, 14, 0))).to contain_exactly([cancun.id, date], [mexico_city.id, date])
    expect(run_at(Time.utc(2026, 10, 6, 15, 0))).to contain_exactly(
      [cancun.id, date], [mexico_city.id, date], [tijuana.id, date]
    )
  end

  it "follows Tijuana onto winter time while the centre, which dropped it in 2022, stays put" do
    tijuana = student("America/Tijuana")
    mexico_city = student("America/Mexico_City")
    november = Date.new(2026, 11, 2)

    expect(run_at(Time.utc(2026, 11, 2, 14, 0))).to eq([[mexico_city.id, november]])
    expect(run_at(Time.utc(2026, 11, 2, 15, 0))).to eq([[mexico_city.id, november]])
    expect(run_at(Time.utc(2026, 11, 2, 16, 0))).to contain_exactly([mexico_city.id, november], [tijuana.id, november])
  end

  it "files the reminder under the student's date, not the server's" do
    student("America/Tijuana").reminder_preference.update!(minute_of_day: 22 * 60)

    # 22:00 in Tijuana on the 6th is already the 7th in UTC.
    expect(run_at(Time.utc(2026, 10, 7, 5, 0)).map(&:last)).to eq([date])
  end

  it "sends nothing twice when runs repeat or overlap" do
    student("America/Mexico_City")

    expect {
      3.times { described_class.perform_now(now: Time.utc(2026, 10, 6, 14, 15)) }
    }.to have_enqueued_mail(RemindersMailer, :reminder).exactly(:once)
  end

  it "leaves out accounts that never proved their address" do
    student("America/Mexico_City", email_verified_at: nil)

    expect(run_at(Time.utc(2026, 10, 6, 14, 0))).to eq([])
  end

  it "does not let one student's failure cost the others their reminder" do
    broken = student("America/Mexico_City")
    fine = student("America/Mexico_City")
    allow(Reminders::Dispatcher).to receive(:call).and_call_original
    allow(Reminders::Dispatcher).to receive(:call).with(hash_including(user: broken)).and_raise("boom")

    expect(run_at(Time.utc(2026, 10, 6, 14, 0))).to eq([[fine.id, date]])
  end

  it "runs every 15 minutes in production" do
    schedule = ActiveSupport::ConfigurationFile.parse(Rails.root.join("config/recurring.yml"))
    task = schedule.dig("production", "send_due_reminders")

    expect(task).to include("class" => described_class.name, "schedule" => "every 15 minutes")
  end
end
