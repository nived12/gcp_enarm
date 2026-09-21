# One chat completion against whichever provider a role resolves to.
#
# Gemini and DeepSeek both speak the OpenAI chat format, so this is the only client the
# pipeline needs; Llm::Provider decides where the request goes and as which model.
#
# Two things here exist because of behaviour measured against the live APIs rather than
# read from their docs. See THINKING and the empty-content check in `extract`.
module Llm
  class Completion < ApplicationService
    NETWORK_ERRORS = Gpc::HttpFetcher::NETWORK_ERRORS

    TIMEOUT_SECONDS = 300
    DEFAULT_MAX_TOKENS = 8_000

    # `deepseek-flash` reasons before answering and bills that reasoning as output. At
    # its default effort it spends roughly 4.6 tokens thinking per token of answer, and
    # under a budget sized for the answer alone it consumes the whole allowance thinking
    # and returns an empty string with finish_reason "length" and no error — a failure
    # that looks exactly like success. Disabling it costs nothing in output quality for
    # generation and cuts output tokens by 4.4x.
    #
    # Gemini reports zero reasoning tokens on the same prompt and ignores the field.
    THINKING = { type: "disabled" }.freeze

    def initialize(role:, prompt:, max_tokens: DEFAULT_MAX_TOKENS, thinking: false)
      super()
      @provider = Llm::Provider.for(role)
      @prompt = prompt
      @max_tokens = max_tokens
      @thinking = thinking
    end

    def call
      return failure("Falta la clave de #{provider.role}") unless provider.configured?

      response = post
      return failure if has_errors?

      extract(response)
    end

    def context_for_logging
      { provider: provider.to_s, role: provider.role }
    end

    private

    attr_reader :provider, :prompt, :max_tokens, :thinking

    def post
      response = HTTParty.post(endpoint, headers: headers, body: body, timeout: TIMEOUT_SECONDS)
      unless response.success?
        failure("#{provider} respondió #{response.code}: #{response.body.to_s.squish.truncate(200)}")
        return nil
      end

      # Parsed here rather than through HTTParty, which decides by Content-Type: a
      # provider that labels its JSON text/plain would otherwise hand back a String and
      # fail several lines later as a NoMethodError.
      JSON.parse(response.body)
    rescue JSON::ParserError
      failure("#{provider} devolvió una respuesta ilegible")
      nil
    rescue *NETWORK_ERRORS => e
      failure("No se pudo llamar a #{provider}: #{e.class} #{e.message}")
      nil
    end

    def endpoint
      "#{provider.base_url.chomp("/")}/chat/completions"
    end

    def headers
      { "Authorization" => "Bearer #{provider.api_key}", "Content-Type" => "application/json" }
    end

    def body
      payload = { model: provider.model, messages: [{ role: "user", content: prompt }],
                  max_tokens: max_tokens }
      payload[:thinking] = THINKING unless thinking
      payload.to_json
    end

    def extract(response)
      choice = response.dig("choices", 0) || {}
      content = choice.dig("message", "content").to_s
      usage = usage_from(response)

      # Empty content with a length stop is the reasoning trap: the model spent the
      # budget thinking. Say so, rather than handing the caller a blank string that
      # will fail much further downstream as "the model wrote nothing useful".
      if content.strip.empty?
        return failure(
          "#{provider} no devolvió contenido " \
                                 "(finish=#{choice["finish_reason"]}, razonamiento=#{usage[:reasoning_tokens]})"
        )
      end

      success(content: content, finish_reason: choice["finish_reason"], **usage)
    end

    def usage_from(response)
      usage = response["usage"] || {}
      { input_tokens: usage["prompt_tokens"].to_i,
        output_tokens: usage["completion_tokens"].to_i,
        reasoning_tokens: usage.dig("completion_tokens_details", "reasoning_tokens").to_i }
    end
  end
end
