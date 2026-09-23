require "rails_helper"

RSpec.describe ExamsHelper, type: :helper do
  it "reads the clock in minutes, and in hours once an exam passes one" do
    expect([helper.clock(65), helper.clock(3_729)]).to eq(["1:05", "1:02:09"])
  end

  it "letters options as the exam does" do
    expect((0..3).map { |index| helper.option_letter(index) }).to eq(%w[A B C D])
  end
end
