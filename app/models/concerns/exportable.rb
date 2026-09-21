# An identity that survives being moved to another database.
#
# Rows whose content is generated have no natural key to match on — a stem is arbitrary
# text the model will never write twice — so they carry a token instead, assigned once and
# never reused. Questions::Importer matches on it, which is what makes importing the same
# file twice a no-op rather than a second copy of a batch that cost real money.
module Exportable
  extend ActiveSupport::Concern

  included do
    before_create { self.export_key ||= SecureRandom.uuid }
  end
end
