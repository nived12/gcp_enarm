require "rails_helper"

RSpec.describe ApplicationService do
  # Named rather than anonymous: failure logging prints self.class.name, and an
  # anonymous class would make those assertions meaningless.
  #
  # `attr_reader :name` is not decoration. Errorable#read_attribute_for_validation
  # sends the attribute name to the service, so a service that adds an error on
  # :name without exposing one raises NoMethodError the moment that error is read.
  # Errors on :base are the only ones that need no reader.
  before do
    stub_const(
      "Greeter", Class.new(ApplicationService) do
                   attr_reader :name

                   def initialize(name = "Gabriela", shout: false)
                     super()
                     @name = name
                     @shout = shout
                   end

                   def call
                     errors.add(:name, :blank, message: "cannot be blank") if name.blank?
                     return failure if has_errors?

                     success(@shout ? "HOLA #{name.upcase}" : "hola #{name}")
                   end

                   def context_for_logging = { name: name }
                 end
    )
  end

  describe ".call" do
    it "forwards positional and keyword arguments to the instance" do
      response = Greeter.call("Gabriela", shout: true)

      expect(response).to be_success
      expect(response.payload).to eq("HOLA GABRIELA")
    end
  end

  describe "#success" do
    it "carries the payload and no errors" do
      response = Greeter.call("Gabriela")

      expect(response.payload).to eq("hola Gabriela")
      expect(response).not_to be_failure
      expect(response.errors).to be_nil
    end

    it "allows an empty payload" do
      expect(described_class.new.success.payload).to be_nil
    end
  end

  describe "#failure" do
    it "reports the errors accumulated during the call" do
      response = Greeter.call("")

      expect(response).to be_failure
      expect(response).not_to be_success
      expect(response.errors.map(&:message)).to include("cannot be blank")
    end

    it "accepts a bare message string" do
      response = described_class.new.failure("la guía no existe")

      expect(response.errors.map(&:message)).to include("la guía no existe")
    end

    it "accepts another object's error bag" do
      other = Greeter.new("")
      other.errors.add(:name, :blank, message: "cannot be blank")

      response = Greeter.new.failure(other.errors)

      expect(response.errors.map(&:attribute)).to eq([:name])
    end

    it "ignores a blank message rather than recording an empty error" do
      response = described_class.new.failure(nil)

      expect(response.errors).to be_empty
      expect(response).to be_failure
    end

    it "logs each error and the service's context" do
      allow(Rails.logger).to receive(:error)

      Greeter.call("")

      expect(Rails.logger).to have_received(:error).with(/Greeter failed with 1 error/)
      expect(Rails.logger).to have_received(:error).with(/name: cannot be blank/)
      expect(Rails.logger).to have_received(:error).with(/Greeter context/)
    end

    it "omits the context block when the service supplies none" do
      allow(Rails.logger).to receive(:error)

      described_class.new.failure("boom")

      expect(Rails.logger).not_to have_received(:error).with(/context/)
    end
  end

  describe "#add_errors_from" do
    it "copies a nested service's errors onto the caller" do
      service = Greeter.new
      service.add_errors_from(Greeter.call(""))

      expect(service).to have_errors
      expect(service.errors.map(&:message)).to include("cannot be blank")
    end

    it "is a no-op for a successful response" do
      service = Greeter.new
      service.add_errors_from(Greeter.call("Gabriela"))

      expect(service).not_to have_errors
    end
  end

  describe "a nil error bag" do
    # errors is a plain accessor, so a subclass that reassigns it can leave it nil.
    # Neither predicate may blow up on that.
    it "reports no errors and clears without raising" do
      service = described_class.new
      service.errors = nil

      expect(service).not_to have_errors
      expect { service.clear_errors }.not_to raise_error
    end
  end

  describe "an unrecognised failure message" do
    it "is dropped rather than coerced into an error" do
      response = described_class.new.failure(:some_symbol)

      expect(response).to be_failure
      expect(response.errors).to be_empty
    end
  end

  describe "#clear_errors" do
    it "empties the bag" do
      service = described_class.new
      service.failure("boom")

      expect { service.clear_errors }.to change { service.has_errors? }.from(true).to(false)
    end
  end
end
