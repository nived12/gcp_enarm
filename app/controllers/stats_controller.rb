class StatsController < ApplicationController
  def show
    @performance = Stats::PerformanceCalculator.call(Current.user).payload
    @streak = Stats::StreakCalculator.call(Current.user).payload
    @coverage = Stats::CoverageCalculator.call(Current.user).payload
  end
end
