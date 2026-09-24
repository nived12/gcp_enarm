class AddDisputesToEntitlements < ActiveRecord::Migration[8.1]
  def change
    # A chargeback is recorded on the purchase it disputes, like a refund. Unlike a refund
    # it can be reversed: `dispute_status` is open while the bank decides, then won or
    # lost, and only an open or lost dispute withholds the window. `dispute_id` names the
    # dispute the status belongs to, so an out-of-order delivery of its own opening event
    # cannot reopen it.
    change_table :entitlements, bulk: true do |t|
      t.string :dispute_id
      t.string :dispute_status
      t.datetime :disputed_at
    end
  end
end
