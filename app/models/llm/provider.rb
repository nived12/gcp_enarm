# Where a generation or verification request goes: which service, as which model, with
# which key.
#
# Every value has a default in code, so a forgotten environment variable degrades to a
# working choice rather than a nil surfacing deep inside a job. The API key is the one
# exception — there is no sensible default for a secret, and a run without one should
# stop somewhere it is obvious why.
#
# Generator and verifier are separate roles that default to different services on
# purpose. The verification pass exists to be a second opinion, and a model grading its
# own output is a much weaker check than another family grading it.
module Llm
  class Provider
    class UnknownProvider < StandardError; end

    # Gemini and DeepSeek both speak the OpenAI chat format, so one client serves
    # either. Gemini's compatibility layer sits under /v1beta/openai/ and the trailing
    # slash is part of the path, not decoration.
    PRESETS = {
      "gemini" => {
        base_url: "https://generativelanguage.googleapis.com/v1beta/openai/",
        model: "gemini-3.1-flash-lite"
      },
      "deepseek" => {
        base_url: "https://api.deepseek.com",
        model: "deepseek-flash"
      },
      "anthropic" => {
        base_url: "https://api.anthropic.com/v1",
        model: "claude-haiku-4-5-20251001"
      }
    }.freeze

    ROLES = {
      generator: { provider: "gemini", prefix: "LLM" },
      verifier: { provider: "deepseek", prefix: "LLM_VERIFIER" }
    }.freeze

    attr_reader :role, :name, :model, :base_url, :api_key

    def self.for(role)
      defaults = ROLES.fetch(role)
      new(role: role, prefix: defaults[:prefix], fallback: defaults[:provider])
    end

    def self.all
      ROLES.keys.map { |role| self.for(role) }
    end

    # Read at call time rather than at class-definition time: a constant captured on
    # load cannot be changed by a spec, and dotenv has not necessarily run yet.
    def initialize(role:, prefix:, fallback:)
      @role = role
      @prefix = prefix
      @name = env("PROVIDER") || fallback
      # Resolved once, and before the overrides are read: a misspelled provider must
      # fail even when MODEL and BASE_URL happen to be set and would mask it.
      preset = PRESETS.fetch(@name) do
        raise UnknownProvider, "#{prefix}_PROVIDER=#{@name.inspect} is not one of #{PRESETS.keys.join(", ")}"
      end
      @model = env("MODEL") || preset.fetch(:model)
      @base_url = env("BASE_URL") || preset.fetch(:base_url)
      @api_key = env("API_KEY")
    end

    def configured?
      api_key.present?
    end

    def to_s
      "#{name}/#{model}"
    end

    private

    attr_reader :prefix

    def env(suffix)
      ENV["#{prefix}_#{suffix}"].presence
    end
  end
end
