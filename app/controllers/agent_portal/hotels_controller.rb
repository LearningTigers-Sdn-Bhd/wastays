# frozen_string_literal: true

module AgentPortal
  class HotelsController < BaseController
    include SheetActionCompletion

    before_action :require_create_permission!, only: [ :new, :create ]

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

    # A superadmin turns hotel creation on for each agent. The invite link
    # works either way.
    def require_create_permission!
      return if current_user.can_create_hotels?

      redirect_to agent_hotels_path, alert: "You cannot create hotels. Share your invite link instead.", status: :see_other
    end

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
