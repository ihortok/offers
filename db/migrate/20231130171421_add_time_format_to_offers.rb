class AddTimeFormatToOffers < ActiveRecord::Migration[7.1]
  def change
    add_column :offers, :time_format, :string
  end
end
