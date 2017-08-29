#-- copyright
# OpenProject is a project management system.
# Copyright (C) 2012-2017 the OpenProject Foundation (OPF)
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License version 3.
#
# OpenProject is a fork of ChiliProject, which is a fork of Redmine. The copyright follows:
# Copyright (C) 2006-2017 Jean-Philippe Lang
# Copyright (C) 2010-2013 the ChiliProject Team
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
# See doc/COPYRIGHT.rdoc for more details.
#++

class GenerateWpClosure < ActiveRecord::Migration[5.0]
  def up
    change_table :relations do |r|
      r.column :depth, :integer
      r.index :depth
    end

    ActiveRecord::Base.connection.execute <<-SQL
      UPDATE relations
      SET depth = 1
    SQL

    ActiveRecord::Base.connection.execute <<-SQL
      INSERT INTO relations
        (from_id, to_id, relation_type, depth)
      SELECT w1.id, w2.id, 'hierarchy', 1
      FROM work_packages w1
      JOIN work_packages w2
      ON w1.id = w2.parent_id
    SQL

    build_closures

    build_self_referential_closures

    change_column_null :relations, :depth, true
  end

  def down
    ActiveRecord::Base.connection.execute <<-SQL
      DELETE FROM relations
      WHERE depth != 1
    SQL

    ActiveRecord::Base.connection.execute <<-SQL
      DELETE FROM relations
      WHERE relation_type = 'hierarchy'
    SQL

    remove_column :relations, :depth
  end

  def build_closures
    say_with_time "building closures" do
      inserted_rows = 1
      depth = 1

      while inserted_rows > 0
        inserted_rows = insert_closure_of_depth(depth)

        circle_results = get_circular(depth)

        unless circle_results.empty?
          say "Circular dependency (#{circle_results}) detected for wich an automated fix (removal) is attempted now"

          remove_first_non_hierarchy_relation(circle_results)

          circle_results = get_circular(depth)

          raise <<-ERROR
           Detected a circular dependency which can not be fixed automatically:

           #{circle_results}

           Please attempt to remove the circular dependency by hand and rerun the migration.
          ERROR
        end

        depth += 1
      end
    end
  end

  def build_self_referential_closures
    say_with_time "building self referential closures" do
      ActiveRecord::Base.connection.execute <<-SQL
        INSERT INTO relations
          (from_id, to_id, depth)
        SELECT id, id, 0
        FROM work_packages
      SQL
    end
  end

  def insert_closure_of_depth(depth)
    result = ActiveRecord::Base.connection.execute <<-SQL
      INSERT INTO relations
        (from_id, to_id, relation_type, depth)
      SELECT
        r1.from_id,
        r2.to_id,
        CASE
          WHEN r1.relation_type = r2.relation_type
          THEN r1.relation_type
          ELSE ''
          END,
        r1.depth + 1
      FROM relations r1
      JOIN relations r2
      ON r1.to_id = r2.from_id AND r1.depth = #{depth} AND r2.depth = 1
    SQL

    result.cmd_tuples
  end

  def get_circular(depth)
    ActiveRecord::Base.connection.select_values <<-SQL
      SELECT r1.from_id, r1.to_id
      FROM relations r1
      JOIN relations r2
      ON r1.from_id = r2.to_id AND r1.to_id = r2.from_id AND r1.depth = 1 AND r2.depth = #{depth}
    SQL
  end

  def remove_first_non_hierarchy_relation(ids)
    ActiveRecord::Base.connection.execute <<-SQL
      DELETE FROM relations
      WHERE id IN (
        SELECT id
        FROM relations
        WHERE from_id IN (#{ids.join(', ')})
        AND to_id IN (#{ids.join(', ')})
        AND relation_type != 'hierarchy'
        AND depth = 1
        LIMIT 1
      )
    SQL
  end
end
