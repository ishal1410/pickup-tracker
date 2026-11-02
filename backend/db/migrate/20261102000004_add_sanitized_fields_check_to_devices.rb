class AddSanitizedFieldsCheckToDevices < ActiveRecord::Migration[8.1]
  def change
    # Before sanitize: no method, no time. From sanitized on: both.
    add_check_constraint :devices,
      "CASE WHEN status IN ('expected', 'received') THEN sanitization_method IS NULL AND sanitized_at IS NULL " \
      "ELSE sanitization_method IS NOT NULL AND sanitized_at IS NOT NULL END",
      name: "devices_sanitized_fields"
  end
end
