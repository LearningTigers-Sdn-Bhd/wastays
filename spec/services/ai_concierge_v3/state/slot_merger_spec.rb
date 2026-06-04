require "rails_helper"

RSpec.describe AiConciergeV3::State::SlotMerger do
  it "resolves adults from a people clarification follow-up" do
    branch = {
      "branch_id" => SecureRandom.uuid,
      "party_size_total" => 2,
      "adults" => nil,
      "children" => nil,
      "suggested_options" => [ { "position" => 1 } ],
      "confirmation_candidate" => { "position" => 1 },
      "selected_option" => { "position" => 1 },
      "selected_rate_plan_id" => 12,
      "selected_rate_plan_name" => "Standard Rate",
      "suggestion_set_version" => 1
    }

    result = described_class.new(active_branch: branch, slots: {}, pending_question: "party_split", message: "adults").call

    expect(result["adults"]).to eq(2)
    expect(result["children"]).to eq(0)
    expect(result["suggested_options"]).to eq([])
  end

  it "leaves children as nil for a partial adult split" do
    branch = {
      "branch_id" => SecureRandom.uuid,
      "party_size_total" => 3,
      "adults" => nil,
      "children" => nil
    }

    result = described_class.new(active_branch: branch, slots: { "adults" => 2 }, pending_question: "party_split", message: "2 adults").call

    expect(result["adults"]).to eq(2)
    expect(result["children"]).to be_nil
  end

  it "resolves the remaining guests as children when user confirms with yes" do
    branch = {
      "branch_id" => SecureRandom.uuid,
      "party_size_total" => 4,
      "adults" => 2,
      "children" => nil
    }

    result = described_class.new(active_branch: branch, slots: { "confirmation" => "yes" }, pending_question: "party_split", message: "yes").call

    expect(result["adults"]).to eq(2)
    expect(result["children"]).to eq(2)
  end

  it "clears adults and children when user says no to the split assumption" do
    branch = {
      "branch_id" => SecureRandom.uuid,
      "party_size_total" => 4,
      "adults" => 2,
      "children" => nil
    }

    result = described_class.new(active_branch: branch, slots: { "confirmation" => "no" }, pending_question: "party_split", message: "no").call

    expect(result["adults"]).to be_nil
    expect(result["children"]).to be_nil
  end

  it "prioritizes extraction over confirmation when explicit counts are present" do
    branch = {
      "branch_id" => SecureRandom.uuid,
      "party_size_total" => 4,
      "adults" => nil,
      "children" => nil
    }

    # Simulate LLM returning confirmation: yes but message has explicit counts
    result = described_class.new(
      active_branch: branch,
      slots: { "confirmation" => "yes" },
      pending_question: "party_split",
      message: "yes 1 adults"
    ).call

    expect(result["adults"]).to eq(1)
    expect(result["children"]).to be_nil
  end

  it "clears stale downstream state when timing changes" do
    branch = {
      "branch_id" => SecureRandom.uuid,
      "target_month" => 7,
      "target_year" => 2026,
      "suggested_options" => [ { "position" => 1 } ],
      "confirmation_candidate" => { "position" => 1 },
      "selected_option" => { "position" => 1 },
      "suggestion_set_version" => 1
    }

    result = described_class.new(active_branch: branch, slots: { "target_month" => 5 }, pending_question: nil, message: "late may").call

    expect(result["target_month"]).to eq(5)
    expect(result["suggested_options"]).to eq([])
    expect(result["confirmation_candidate"]).to be_nil
    expect(result["selected_option"]).to be_nil
    expect(result["selected_rate_plan_id"]).to be_nil
    expect(result["selected_rate_plan_name"]).to be_nil
  end

  it "derives nights and check-out from days and check-in" do
    branch = {
      "branch_id" => SecureRandom.uuid,
      "check_in" => nil,
      "check_out" => nil,
      "nights" => nil,
      "days" => nil
    }

    result = described_class.new(
      active_branch: branch,
      slots: { "check_in" => "2026-08-03", "days" => 3 },
      pending_question: nil,
      message: "check in august 3 for 3 days"
    ).call

    expect(result["nights"]).to eq(2)
    expect(result["check_out"]).to eq("2026-08-05")
  end
end
