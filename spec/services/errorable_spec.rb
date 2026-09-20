require "rails_helper"

RSpec.describe Errorable do
  subject(:service) { Greeter.new }

  before do
    stub_const(
      "Greeter", Class.new do
                   include Errorable

                   attr_reader :name, :errors

                   def initialize(name = "Gabriela")
                     @name = name
                     @secret = "no reader for this one"
                     @errors = ActiveModel::Errors.new(self)
                   end
                 end
    )
  end

  it "satisfies the interface ActiveModel::Errors expects of its base" do
    expect(Greeter.human_attribute_name(:name)).to eq(:name)
    expect(Greeter.lookup_ancestors).to eq([Greeter])
    expect(service.read_attribute_for_validation(:name)).to eq("Gabriela")
  end

  describe "#attributes" do
    it "exposes readable instance variables and nils the rest" do
      expect(service.attributes).to include("name" => "Gabriela")
      expect(service.attributes).to have_key("errors")
      expect(service.attributes).to include("secret" => nil)
    end
  end

  describe "#valid?" do
    it "is true while the bag is empty and false once an error is added" do
      expect(service).to be_valid

      service.errors.add(:name, :invalid, message: "no sirve")

      expect(service).not_to be_valid
    end
  end
end
