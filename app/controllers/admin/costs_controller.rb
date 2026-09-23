# What the LLM work has cost, from the GenerationRun rows every batch writes. Read-only:
# nothing here calls a provider.
module Admin
  class CostsController < BaseController
    before_action :require_admin

    def show
      @rows = GenerationRun.group(:purpose, :provider, :model)
                           .order(Arel.sql("SUM(cost_usd) DESC"))
                           .pluck(:purpose, :provider, :model, Arel.sql("COUNT(*)"), Arel.sql("SUM(input_tokens)"),
                             Arel.sql("SUM(output_tokens)"), Arel.sql("SUM(cost_usd)")
                           )
                           .map { |row| Row.new(*row) }
      @by_purpose = @rows.group_by(&:purpose).transform_values { |rows| rows.sum(&:cost) }.sort_by { |_, cost| -cost }
      @total = Row.new("total", nil, nil, *%i[runs input_tokens output_tokens cost].map { |field| @rows.sum(&field) })
    end

    Row = Struct.new(:purpose, :provider, :model, :runs, :input_tokens, :output_tokens, :cost)
  end
end
