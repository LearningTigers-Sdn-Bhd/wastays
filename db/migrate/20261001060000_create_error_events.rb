class CreateErrorEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :error_events do |t|
      t.string :error_class, null: false
      t.text :message
      t.text :backtrace
      t.string :severity, null: false, default: "error"
      t.boolean :handled, null: false, default: false
      t.string :source
      t.jsonb :context, null: false, default: {}
      t.datetime :occurred_at, null: false

      t.timestamps
    end

    add_index :error_events, :occurred_at
  end
end
