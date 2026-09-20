# frozen_string_literal: true

##
# Errorable
# Concern module to include and manage ActiveModel like errors bag
#
# Usage:
# include Errorable in your service class and declare:
#   @errors = ActiveModel::Errors.new(self)
# in the initializer then you can validate your service class and add errors to @error
#   errors.add(:base, :name, message: "cannot be nil") if name.nil?
#
module Errorable
  # Class methods
  module ClassMethods
    # required by active model errors
    def human_attribute_name(attr, _options = {})
      attr
    end

    # required by active model errors
    def lookup_ancestors
      [ self ]
    end
  end

  # this method will be called on including the concern
  def self.included(base)
    base.extend(ActiveModel::Naming)
    base.extend(ClassMethods)
  end

  # required by active model errors
  def read_attribute_for_validation(attr)
    send(attr)
  end

  ##
  # return hash of class attributes
  #
  def attributes
    attrs = {}
    instance_variables.each do |key|
      attr = key.to_s.delete("@")
      attrs[attr] = respond_to?(attr) ? send(attr) : nil
    end
    attrs
  end

  ##
  # Check if the class is valid or not
  #
  # @return [Boolean] true|false
  #
  def valid?
    errors.empty?
  end
end
