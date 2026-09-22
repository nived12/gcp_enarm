require "rails_helper"

RSpec.describe Llm::Provider do
  def with_env(values)
    original = ENV.to_h.slice(*values.keys)
    values.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    yield
  ensure
    values.each_key { |key| ENV.delete(key) }
    original.each { |key, value| ENV[key] = value }
  end

  describe ".for" do
    it "defaults the generator to Gemini without any environment set" do
      with_env("LLM_PROVIDER" => nil, "LLM_MODEL" => nil, "LLM_BASE_URL" => nil, "LLM_API_KEY" => nil) do
        provider = described_class.for(:generator)

        expect(provider.name).to eq("gemini")
        expect(provider.model).to eq("gemini-3.1-flash-lite")
        expect(provider.base_url).to eq("https://generativelanguage.googleapis.com/v1beta/openai/")
        expect(provider.api_key).to be_nil
        expect(provider).not_to be_configured
      end
    end

    it "defaults the verifier to a different family than the generator" do
      with_env("LLM_VERIFIER_PROVIDER" => nil, "LLM_VERIFIER_MODEL" => nil) do
        verifier = described_class.for(:verifier)

        expect(verifier.name).to eq("deepseek")
        expect(verifier.model).to eq("deepseek-flash")
        expect(verifier.name).not_to eq(described_class::ROLES.fetch(:generator).fetch(:provider))
      end
    end

    it "reads the key from the environment and reports itself configured" do
      with_env("LLM_API_KEY" => "sk-test") do
        expect(described_class.for(:generator)).to be_configured
      end
    end

    it "treats a blank key as absent" do
      with_env("LLM_API_KEY" => "   ") do
        provider = described_class.for(:generator)

        expect(provider.api_key).to be_nil
        expect(provider).not_to be_configured
      end
    end

    it "lets the environment override the service, the model and the endpoint" do
      with_env(
        "LLM_PROVIDER" => "deepseek", "LLM_MODEL" => "deepseek-v4-pro",
        "LLM_BASE_URL" => "https://proxy.example/v1"
      ) do
        provider = described_class.for(:generator)

        expect(provider.name).to eq("deepseek")
        expect(provider.model).to eq("deepseek-v4-pro")
        expect(provider.base_url).to eq("https://proxy.example/v1")
      end
    end

    it "falls back to the preset endpoint when only the service is overridden" do
      with_env("LLM_PROVIDER" => "anthropic", "LLM_MODEL" => nil, "LLM_BASE_URL" => nil) do
        provider = described_class.for(:generator)

        expect(provider.model).to eq("claude-haiku-4-5-20251001")
        expect(provider.base_url).to eq("https://api.anthropic.com/v1")
      end
    end

    it "refuses a service it has no preset for, naming the ones it has" do
      with_env("LLM_PROVIDER" => "gemeni") do
        expect { described_class.for(:generator) }
          .to raise_error(described_class::UnknownProvider, /LLM_PROVIDER="gemeni".*gemini, deepseek, anthropic/)
      end
    end

    it "refuses a misspelled service even when the model and endpoint are set" do
      with_env("LLM_PROVIDER" => "openai", "LLM_MODEL" => "gpt-4", "LLM_BASE_URL" => "https://example.com") do
        expect { described_class.for(:generator) }.to raise_error(described_class::UnknownProvider)
      end
    end

    it "raises for a role that does not exist" do
      expect { described_class.for(:summariser) }.to raise_error(KeyError)
    end
  end

  describe ".all" do
    it "returns every role" do
      expect(described_class.all.map(&:role)).to eq(%i[generator verifier])
    end
  end

  describe "#cost_for" do
    it "prices tokens at the model's published rate" do
      with_env("LLM_VERIFIER_PROVIDER" => nil, "LLM_VERIFIER_MODEL" => nil) do
        verifier = described_class.for(:verifier)

        expect(verifier).to be_priced
        expect(verifier.cost_for(input_tokens: 1_000_000, output_tokens: 1_000_000)).to eq(1.5)
      end
    end

    it "prices a model it has no rate for at nothing, and says so" do
      with_env("LLM_MODEL" => "gemini-9-experimental") do
        provider = described_class.for(:generator)

        expect(provider).not_to be_priced
        expect(provider.cost_for(input_tokens: 1_000, output_tokens: 1_000)).to eq(0)
      end
    end
  end

  describe "#to_s" do
    it "names the service and the model, for a run's log" do
      with_env("LLM_PROVIDER" => nil, "LLM_MODEL" => nil) do
        expect(described_class.for(:generator).to_s).to eq("gemini/gemini-3.1-flash-lite")
      end
    end
  end
end
