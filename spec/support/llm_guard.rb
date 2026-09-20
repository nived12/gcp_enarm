# A spec that reaches a real LLM costs money, is non-deterministic, and will fail in CI
# without keys. WebMock already blocks outbound HTTP, but its default error names the URL
# without explaining why — this turns the generic failure into an actionable one.
LLM_HOSTS = %w[
  api.deepseek.com
  generativelanguage.googleapis.com
  api.anthropic.com
  api.openai.com
].freeze

RSpec.configure do |config|
  config.before(:suite) do
    WebMock.disable_net_connect!(allow_localhost: true)

    LLM_HOSTS.each do |host|
      WebMock.stub_request(:any, /#{Regexp.escape(host)}/).to_raise(
        <<~MESSAGE
          Spec attempted a live LLM call to #{host}.
          Stub the Llm client instead — see spec/support/llm_stubs.rb.
        MESSAGE
      )
    end
  end
end
