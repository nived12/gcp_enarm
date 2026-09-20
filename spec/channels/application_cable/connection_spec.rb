require "rails_helper"

RSpec.describe ApplicationCable::Connection, type: :channel do
  let(:user) { create(:user) }

  it "identifies the connection from the signed session cookie" do
    session = create(:session, user: user)
    cookies.signed[:session_id] = session.id

    connect "/cable"

    expect(connection.current_user).to eq(user)
  end

  it "rejects a connection with no session cookie" do
    expect { connect "/cable" }.to have_rejected_connection
  end

  it "rejects a connection whose session row is gone" do
    session = create(:session, user: user)
    cookies.signed[:session_id] = session.id
    session.destroy

    expect { connect "/cable" }.to have_rejected_connection
  end
end
