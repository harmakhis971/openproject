class GenerateWpClosure < ActiveRecord::Migration[5.0]
  def up
    change_table :relations do |r|
      r.column :depth, :integer
    end

    ActiveRecord::Base.connection.execute <<-SQL
      UPDATE relations
      SET depth = 1
    SQL

    ActiveRecord::Base.connection.execute <<-SQL
      INSERT INTO relations
        (from_id, to_id, depth)
      SELECT id, id, 0
      FROM (SELECT DISTINCT(id) FROM (SELECT from_id id FROM relations UNION SELECT to_id id FROM relations) relations) relations
    SQL

    change_column_null :relations, :depth, true
  end

  def down
    ActiveRecord::Base.connection.execute <<-SQL
      DELETE FROM relations
      WHERE depth = 0
    SQL

    remove_column :relations, :depth
  end
end
