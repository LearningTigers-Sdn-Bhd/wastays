# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::KnowledgeDocuments", type: :request do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: "admin") }
  let(:hotel) { create(:hotel, account: account, status: "approved") }
  let(:role) { create(:role, account: account, slug: "hotel_owner", name: "Hotel Owner") }

  before do
    Permission.find_or_create_by!(slug: "manage_hotel_profile") { |permission| permission.name = "Manage Hotel Profile" }
    RolePermission.find_or_create_by!(role: role, permission: Permission.find_by!(slug: "manage_hotel_profile"))
    UserRole.create!(user: user, role: role)
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  shared_examples "a knowledge resource" do |category:, route_prefix:, index_title:, create_params: {}|
    let!(:doc) { create(:hotel_knowledge_document, hotel: hotel, category: category, title: "Test Doc") }
    let(:index_path) { public_send("#{route_prefix.pluralize}_path", hotel) }
    let(:new_path) { public_send("new_#{route_prefix}_path", hotel) }
    let(:show_path) { public_send("#{route_prefix}_path", hotel, doc) }
    let(:edit_path) { public_send("edit_#{route_prefix}_path", hotel, doc) }
    let(:reindex_path) { public_send("reindex_#{route_prefix}_path", hotel, doc) }

    describe "GET index" do
      it "renders the index page" do
        get index_path

        expect(response).to have_http_status(:ok)
        expect(response.body).to include(index_title)
      end

      it "lists existing documents scoped to #{category}" do
        get index_path

        expect(response.body).to include("Test Doc")
      end
    end

    describe "GET new" do
      it "renders the new form" do
        get new_path

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Add Document")
      end
    end

    describe "POST create" do
      it "creates a document with #{category} category" do
        expect {
          post index_path, params: {
            hotel_knowledge_document: {
              title: "New #{category}",
              source_type: "text",
              content: "Content"
            }.merge(create_params)
          }
        }.to change(HotelKnowledgeDocument, :count).by(1)

        expect(response).to redirect_to(index_path)
        new_doc = HotelKnowledgeDocument.last
        expect(new_doc.title).to eq("New #{category}")
        expect(new_doc.category).to eq(category)
        expect(new_doc.content).to be_present
      end

      it "rejects invalid documents" do
        post index_path, params: {
          hotel_knowledge_document: { title: "", source_type: "" }
        }

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("Add Document")
      end
    end

    describe "GET show" do
      it "shows the document" do
        get show_path

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Test Doc")
      end

      it "does not show manual embedding controls when AI Concierge is disabled" do
        get show_path

        expect(response.body).not_to include("Generate Embeddings")
        expect(response.body).not_to include("Retry Embeddings")
      end
    end

    describe "POST reindex" do
      it "does not enqueue embedding generation when AI Concierge is disabled" do
        expect {
          post reindex_path
        }.not_to have_enqueued_job(HotelKnowledges::GenerateEmbeddingsJob)

        expect(response).to redirect_to(show_path)
      end

      it "enqueues embedding generation when AI Concierge is enabled" do
        hotel.update!(ai_provider_enabled: true, ai_provider_name: "openai", ai_provider_key: "sk-test-key")

        expect {
          post reindex_path
        }.to have_enqueued_job(HotelKnowledges::GenerateEmbeddingsJob).with(doc.id)

        expect(response).to redirect_to(show_path)
      end
    end

    describe "PATCH update" do
      it "updates a document" do
        patch show_path, params: {
          hotel_knowledge_document: { title: "Updated Title" }
        }

        expect(response).to redirect_to(index_path)
        expect(doc.reload.title).to eq("Updated Title")
      end
    end

    describe "DELETE destroy" do
      it "deletes a document" do
        expect {
          delete show_path
        }.to change(HotelKnowledgeDocument, :count).by(-1)

        expect(response).to redirect_to(index_path)
      end

      it "deletes associated chunks" do
        doc.chunks.create!(content: "Chunk", chunk_index: 0)

        expect {
          delete show_path
        }.to change(HotelKnowledgeChunk, :count).by(-1)
      end
    end
  end

  it_behaves_like "a knowledge resource",
    category: "policy",
    route_prefix: "hotel_knowledge_policy",
    index_title: "Policy Management"

  it_behaves_like "a knowledge resource",
    category: "faq",
    route_prefix: "hotel_knowledge_faq",
    index_title: "FAQs Management",
    create_params: {
      metadata: { qa_pairs: [ { question: "What time is check-in?", answer: "3:00 PM" } ] }
    }

  it_behaves_like "a knowledge resource",
    category: "general_info",
    route_prefix: "hotel_knowledge_general_info",
    index_title: "General Info Management"
end
