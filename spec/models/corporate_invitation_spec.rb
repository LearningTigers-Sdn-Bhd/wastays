# frozen_string_literal: true

require "rails_helper"

RSpec.describe CorporateInvitation, type: :model do
  it "uses reusable JSONB metadata instead of corporate-specific columns" do
    metadata_column = Invitation.columns_hash.fetch("metadata")

    expect(metadata_column.type).to eq(:jsonb)
    expect(metadata_column.null).to be(false)
    expect(metadata_column.default).to eq("{}")
    expect(Invitation.column_names).not_to include(
      "company_name",
      "corporate_type",
      "relationship_type",
      "direct_bill_enabled",
      "credit_limit",
      "credit_currency",
      "payment_terms_days"
    )
  end

  it "uses the shared invitation table and corporate kind" do
    invitation = create(:corporate_invitation)

    expect(invitation.kind).to eq("corporate")
    expect(Invitation.find(invitation.id)).to have_attributes(
      id: invitation.id,
      kind: "corporate",
      email: invitation.email
    )
  end

  it "stores and type-casts corporate proposal attributes in metadata" do
    invitation = build(
      :corporate_invitation,
      relationship_type: "direct_bill",
      credit_limit: "5000.25",
      payment_terms_days: "30"
    )

    expect(invitation).to be_valid
    expect(invitation.direct_bill_enabled).to be(true)
    expect(invitation.credit_limit).to eq(5000.25.to_d)
    expect(invitation.payment_terms_days).to eq(30)
    expect(invitation.metadata).to include(
      "relationship_type" => "direct_bill",
      "direct_bill_enabled" => true,
      "credit_limit" => "5000.25",
      "payment_terms_days" => 30
    )
  end

  it "requires corporate relationship attributes" do
    invitation = build(:corporate_invitation, relationship_type: nil)

    expect(invitation).not_to be_valid
    expect(invitation.errors[:relationship_type]).to be_present
  end

  it "enforces the corporate relationship metadata constraint in the database" do
    invitation = create(:corporate_invitation)

    expect {
      invitation.update_column(:metadata, {})
    }.to raise_error(ActiveRecord::StatementInvalid)
  end
end
