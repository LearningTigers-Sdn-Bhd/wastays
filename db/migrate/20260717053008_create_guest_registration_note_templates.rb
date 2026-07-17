class CreateGuestRegistrationNoteTemplates < ActiveRecord::Migration[8.0]
  def change
    create_table :guest_registration_note_templates do |t|
      t.references :hotel, null: false, foreign_key: true
      t.string :title
      t.text :content

      t.timestamps
    end
  end
end
