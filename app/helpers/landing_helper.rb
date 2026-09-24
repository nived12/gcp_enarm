module LandingHelper
  # The bank's size the way a person says it: rounded down to two significant figures
  # (tens at least) with a "+", so "427" reads "420+" and "10,432" reads "10,000+". Down,
  # never up, because the page must not claim a question that is not there; an exact
  # round number keeps no "+".
  def bank_count(count)
    return number_with_delimiter(count) if count < 10

    step = [10, 10**(count.digits.size - 2)].max
    floored = count - (count % step)
    floored == count ? number_with_delimiter(count) : "#{number_with_delimiter(floored)}+"
  end
end
