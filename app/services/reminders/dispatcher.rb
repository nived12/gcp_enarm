# Decides what one student is owed right now, claims it, and sends it.
#
# The rules, all opt-in:
#
# * a study-day reminder at the student's chosen time, on a day their plan has work on
#   it, unless they already studied;
# * otherwise, a streak nudge at 20:00 when a streak is running and today does not count
#   yet. The two share one daily slot, so the student gets at most one of them a day;
#   on a day the study reminder covers, the nudge never fires;
# * an exam countdown at the chosen time 30, 7 and 1 days before the exam. When it falls
#   on the same run as the study reminder, both go out as one message.
#
# Every kind is claimed in ReminderDelivery before it is sent, so overlapping runs, or a
# run repeated after a crash, cannot send the same thing twice.
module Reminders
  class Dispatcher < ApplicationService
    COUNTDOWN_DAYS = [30, 7, 1].freeze

    def initialize(user:, now: Time.current)
      super()
      @user = user
      @now = now
    end

    def call
      return success([]) if channels.empty?

      claimed = due_kinds.select do |kind|
        ReminderDelivery.claim(user: user, local_date: today, kind: kind, channels: channels)
      end
      deliver(claimed) if claimed.any?
      success(claimed)
    end

    private

    attr_reader :user, :now

    def preference
      user.reminder_settings
    end

    def channels
      @channels ||= [].tap do |list|
        list << "push" if PushSubscription.enabled? && user.push_subscriptions.exists?
        list << "email" if preference.by_email
      end
    end

    def local_time
      @local_time ||= now.in_time_zone(user.time_zone)
    end

    def today
      local_time.to_date
    end

    def due_kinds
      [countdown_kind, daily_kind].compact
    end

    def countdown_kind
      return unless preference.exam_countdown && plan && COUNTDOWN_DAYS.include?((plan.exam_date - today).to_i)

      "exam_countdown" if ReminderPreference.due_at?(preference.minute_of_day, local_time)
    end

    def daily_kind
      if preference.study_days && plan_day_has_work?
        "study_day" if ReminderPreference.due_at?(preference.minute_of_day, local_time) && !studied_today?
      elsif preference.streak_at_risk && ReminderPreference.due_at?(ReminderPreference::STREAK_MINUTE, local_time)
        "streak_at_risk" if streak.state == :active && !streak.today_done
      end
    end

    # A catch-up day is slack, not work: it asks for nothing by name.
    def plan_day_has_work?
      plan_day.present? && !plan_day.kind_catch_up?
    end

    def studied_today?
      streak.today_done || plan_day.done?
    end

    def plan
      @plan ||= user.study_plan
    end

    def plan_day
      return @plan_day if defined?(@plan_day)

      @plan_day = plan&.day_on(today)
    end

    def streak
      @streak ||= Stats::StreakCalculator.call(user, today: today).payload
    end

    def deliver(kinds)
      message = ReminderMessage.new(kinds: kinds, date: today, plan: plan, plan_day: plan_day, streak: streak).to_h
      RemindersMailer.reminder(user, message).deliver_later if channels.include?("email")
      return unless channels.include?("push")

      payload = ApplicationController.render(
        template: "push_notifications/reminder", formats: [:json],
        locals: { message: message }
      )
      # Worthless after midnight: tomorrow brings its own.
      ttl = (user.study_day_times(today).end - now).to_i
      user.push_subscriptions.each { |subscription| PushNotificationJob.perform_later(subscription, payload, ttl) }
    end
  end
end
