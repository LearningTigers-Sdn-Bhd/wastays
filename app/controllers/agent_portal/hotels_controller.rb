# frozen_string_literal: true

module AgentPortal
  class HotelsController < BaseController
    include SheetActionCompletion

    def index
      @hotels = current_user.created_hotels.order(created_at: :desc)
    end

    def new
      @form = AgentPortal::Hotels::CreateForm.new
    end

    def create
      @form = AgentPortal::Hotels::CreateForm.new(create_params)

      if @form.save(actor: current_user)
        stash_owner_credentials
        complete_sheet_action(destination: agent_hotels_path, notice: "Hotel created.", frame: "agent_hotel_action_sheet")
      else
        render :new, status: :unprocessable_content
      end
    end

    private

    def create_params
      params.fetch(:agent_portal_hotels_create_form, {})
        .permit(*AgentPortal::Hotels::CreateForm::AGENT_FIELDS)
    end

    # The password is shown once, on the page after the redirect. Flash rides
    # in the encrypted session cookie and clears itself after one render.
    def stash_owner_credentials
      flash[:owner_credentials] = {
        "email" => @form.owner.email,
        "password" => @form.generated_password
      }
    end
  end
end
