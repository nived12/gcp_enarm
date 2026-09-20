# frozen_string_literal: true

# Base class for every service object. Services return a Response rather than raising:
# callers branch on `result.success?` and read `result.payload` or `result.errors`.
#
#   class Gpc::CatalogFetcher < ApplicationService
#     def initialize(source) = (super(); @source = source)
#
#     def call
#       fetch
#       return failure if has_errors?
#
#       success(guidelines)
#     end
#   end
class ApplicationService
  include Errorable

  def self.call(*args, **kwargs, &block)
    new(*args, **kwargs, &block).call
  end

  attr_accessor :errors

  def initialize
    @errors = ActiveModel::Errors.new(self)
  end

  def success(payload = nil)
    Response.new(success: true, payload: payload, errors: nil)
  end

  # Every failure logs itself, plus whatever context_for_logging returns. Services that
  # fail silently are the ones that cost an afternoon later.
  def failure(error_message = nil)
    add_error_message(error_message)
    log_errors if has_errors?

    Response.new(success: false, payload: nil, errors: errors)
  end

  def has_errors?
    errors&.any? || false
  end

  def clear_errors
    errors&.clear
  end

  def add_errors_from(response)
    return unless response.errors&.any?

    response.errors.each { |error| errors.add(error.attribute, error.type, message: error.message) }
  end

  # Override to attach identifying context to a failure log.
  def context_for_logging
    {}
  end

  private

  def add_error_message(error_message)
    return if error_message.blank?

    case error_message
    when String
      errors.add(:base, error_message)
    when ActiveModel::Errors
      error_message.each { |error| errors.add(error.attribute, error.type, message: error.message) }
    end
  end

  def log_errors
    Rails.logger.error("#{self.class.name} failed with #{errors.count} error(s):")
    errors.each do |error|
      field = error.attribute == :base ? "base" : error.attribute
      Rails.logger.error("  #{field}: #{error.message}")
    end

    return if context_for_logging.blank?

    Rails.logger.error("#{self.class.name} context:")
    context_for_logging.each { |key, value| Rails.logger.error("  #{key}: #{value}") }
  end

  class Response
    attr_reader :success, :payload, :errors

    def initialize(success:, payload:, errors:)
      @success = success
      @payload = payload
      @errors = errors
    end

    def success? = @success
    def failure? = !@success
  end
end
