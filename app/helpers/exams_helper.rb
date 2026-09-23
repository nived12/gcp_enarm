module ExamsHelper
  # Lettered as on the real exam, and as the verifier reads them.
  def option_letter(index)
    Questions::Verifier::LETTERS[index]
  end

  # 9:05, or 1:02:09 once an exam passes the hour: an ENARM-length sitting runs for hours.
  def clock(seconds)
    hours, rest = seconds.to_i.divmod(3600)
    minutes, secs = rest.divmod(60)
    hours.positive? ? format("%d:%02d:%02d", hours, minutes, secs) : format("%d:%02d", minutes, secs)
  end

  # What the clock on screen shows: time left when the exam has a limit, time spent when
  # it does not.
  def clock_reading(exam)
    clock(exam.remaining_seconds || exam.current_elapsed)
  end

  def score_text(score)
    number_to_percentage(score, precision: 1, strip_insignificant_zeros: true)
  end
end
