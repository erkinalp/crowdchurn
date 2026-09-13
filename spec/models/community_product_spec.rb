# frozen_string_literal: true

require "spec_helper"

RSpec.describe CommunityProduct do
  let(:seller) { create(:user) }
  let(:community) { create(:community, seller:, resource: create(:product, user: seller)) }
  let(:product) { create(:product, user: seller) }

  it "links multiple products from the same seller without duplicate associations" do
    community.add_product!(product)
    community.add_product!(product)
    another_product = create(:product, user: seller)
    community.add_product!(another_product)

    expect(community.linked_products).to contain_exactly(product, another_product)
    expect(community.all_products).to contain_exactly(community.resource, product, another_product)
    expect(product.shared_communities).to eq([community])
    expect(described_class.count).to eq(2)
  end

  it "rejects a product from another seller through both entry points" do
    other_product = create(:product)

    expect { community.add_product!(other_product) }.to raise_error(ArgumentError, /same seller/)
    expect { described_class.create!(community:, product: other_product) }
      .to raise_error(ActiveRecord::RecordInvalid, /same seller/)
  end

  it "validates uniqueness and enforces it in the database" do
    community.add_product!(product)
    duplicate = described_class.new(community:, product:)

    expect(duplicate).not_to be_valid
    expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "removes only the selected product" do
    community.add_product!(product)
    another_product = create(:product, user: seller)
    community.add_product!(another_product)

    community.remove_product!(product)

    expect(community.linked_products).to eq([another_product])
    expect(community).to be_alive
  end

  it "preserves a custom name with a fallback to the source product" do
    community.update!(name: "Shared classroom")
    expect(community.reload.name).to eq("Shared classroom")

    community.update!(name: " ")
    expect(community.reload.name).to eq(community.resource.name)
  end
end
