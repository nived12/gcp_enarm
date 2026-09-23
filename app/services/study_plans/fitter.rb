module StudyPlans
  # Lays an ordered list of slots onto the study dates left, one slot a date, keeping
  # their order. It is how a plan survives a student falling behind or moving the exam.
  #
  # With dates to spare, the extra ones become review days just before the last slot,
  # the final simulacro. With too few, the plan gives way in a fixed order, and never
  # drops a topic: first the catch-up days, which exist to be given up; then the mixed
  # reviews, the workshops and the earlier simulacros, all practice a topic day already
  # quizzed; and only then two topic days of the same pass become one, the latest pass
  # and the lightest pair first, so the thorough first reading is the last to thicken.
  class Fitter
    GIVES_WAY = %w[catch_up review case_workshop assessment].freeze

    def self.fit(slots, dates)
      new(slots, dates).fit
    end

    def initialize(slots, dates)
      @slots = slots.dup
      @dates = dates
    end

    # [[date, slot], …], or nil when not even merging leaves one date a slot.
    def fit
      return [] if slots.empty?

      pad if slots.size < dates.size
      shrink if slots.size > dates.size
      dates.zip(slots) if slots.size <= dates.size
    end

    private

    attr_reader :slots, :dates

    def pad
      last = slots.pop
      slots.concat(Array.new(dates.size - slots.size - 1) { Slot.for("review", last.pass_number) }) << last
    end

    def shrink
      GIVES_WAY.each do |kind|
        while slots.size > dates.size && (index = slots[0...-1].index { |slot| slot.kind == kind })
          slots.delete_at(index)
        end
      end
      nil while slots.size > dates.size && merge_lightest_pair
    end

    def merge_lightest_pair
      index = (0...slots.size - 1).select { |i| mergeable?(slots[i], slots[i + 1]) }.min_by do |i|
        [-slots[i].pass_number, slots[i].topic_ids.size + slots[i + 1].topic_ids.size, i]
      end
      return false unless index

      slots[index, 2] = [slots[index].merge(slots[index + 1])]
      true
    end

    def mergeable?(first, second)
      first.topics? && second.topics? && first.pass_number == second.pass_number
    end
  end
end
