# frozen_string_literal: true

require "spec_helper"
require "shared_examples/admin_base_controller_concern"

describe Admin::Compliance::GuidsController do
  it_behaves_like "inherits from Admin::BaseController"

  let(:admin_user) { create(:admin_user) }
  let(:users) { create_list(:user, 3) }
  let(:user1) { users[0] }
  let(:user2) { users[1] }
  let(:user3) { users[2] }
  let(:browser_guid1) { SecureRandom.uuid }
  let(:browser_guid2) { SecureRandom.uuid }
  let(:browser_guid3) { SecureRandom.uuid }

  before do
    create_list(:event, 2, user_id: user1.id, browser_guid: browser_guid1)

    create_list(:event, 2, user_id: user1.id, browser_guid: browser_guid2)
    create_list(:event, 2, user_id: user2.id, browser_guid: browser_guid2)

    create_list(:event, 2, user_id: user1.id, browser_guid: browser_guid3)
    create_list(:event, 2, user_id: user2.id, browser_guid: browser_guid3)
    create_list(:event, 2, user_id: user3.id, browser_guid: browser_guid3)

    sign_in admin_user
  end

  describe "GET 'index'" do
    it "returns unique browser GUIDs with unique user IDs for the supplied user ID" do
      get :index, params: { user_id: user1.id }

      expect(response).to be_successful

      expected_value = [
        { "guid" => browser_guid1, "user_ids" => [user1.id] },
        { "guid" => browser_guid2, "user_ids" => [user1.id, user2.id] },
        { "guid" => browser_guid3, "user_ids" => [user1.id, user2.id, user3.id] }
      ]

      expect(response.parsed_body).to match_array(expected_value)
    end
  end
end
