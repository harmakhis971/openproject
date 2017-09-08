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
      relation_types.each do |column|
        r.column column, :integer, default: 0
        r.index column
      end
    end

    ActiveRecord::Base.connection.execute <<-SQL
      UPDATE
        relations
      SET
        relates =    CASE
                     WHEN relations.relation_type = 'relates'
                     THEN 1
                     ELSE 0
                     END,
        duplicates = CASE
                     WHEN relations.relation_type = 'duplicates'
                     THEN 1
                     ELSE 0
                     END,
        blocks =     CASE
                     WHEN relations.relation_type = 'blocks'
                     THEN 1
                     ELSE 0
                     END,
        precedes =   CASE
                     WHEN relations.relation_type = 'precedes'
                     THEN 1
                     ELSE 0
                     END,
        includes =   CASE
                     WHEN relations.relation_type = 'includes'
                     THEN 1
                     ELSE 0
                     END,
        requires =   CASE
                     WHEN relations.relation_type = 'requires'
                     THEN 1
                     ELSE 0
                     END
    SQL

    ActiveRecord::Base.connection.execute <<-SQL
      INSERT INTO relations
        (from_id, to_id, hierarchy)
      SELECT w1.id, w2.id, 1
      FROM work_packages w1
      JOIN work_packages w2
      ON w1.id = w2.parent_id
    SQL

    build_closures

    relation_types.each do |column|
      change_column_null :relations, column, true
    end
  end

  def down
    ActiveRecord::Base.connection.execute <<-SQL
      DELETE FROM relations
      WHERE hierarchy > 0
      OR #{relation_types.map { |column| "#{column} > 1" }.join(' OR ')}
    SQL

    relation_types.each do |column|
      remove_column :relations, column
    end

    #ActiveRecord::Base.connection.execute <<-SQL
    #  DELETE FROM relations
    #  WHERE relation_type = 'hierarchy'
    #SQL

    #remove_column :relations, :depth
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

  def insert_closure_of_depth(depth)
    result = ActiveRecord::Base.connection.execute <<-SQL
      INSERT INTO relations
        (from_id,
         to_id,
         hierarchy,
         relates,
         duplicates,
         blocks,
         precedes,
         includes,
         requires)
      SELECT
        r1.from_id,
        r2.to_id,
        r1.hierarchy + r2.hierarchy,
        r1.relates + r2.relates,
        r1.duplicates + r2.duplicates,
        r1.blocks + r2.blocks,
        r1.precedes + r2.precedes,
        r1.includes + r2.includes,
        r1.requires + r2.requires
      FROM relations r1
      JOIN relations r2
      ON r1.to_id = r2.from_id
      AND (#{sum_of_columns(relation_types, 'r1.')} = #{depth})
      AND (#{sum_of_columns(relation_types, 'r2.')} = 1)
    SQL

    result.try(:cmd_tuples) || 0
  end

  def get_circular(depth)
    ActiveRecord::Base.connection.select_values <<-SQL
      SELECT r1.from_id, r1.to_id
      FROM relations r1
      JOIN relations r2
      ON r1.from_id = r2.to_id
      AND r1.to_id = r2.from_id
      AND (#{sum_of_columns(relation_types, 'r1.')} = 1)
      AND (#{sum_of_columns(relation_types, 'r2.')} = #{depth})
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
        AND hierarchy != 1
        AND #{exactly_one_column_eql_1(relation_types - [:hierarchy])}
        LIMIT 1
      )
    SQL
  end

  def relation_types
    %i(hierarchy relates duplicates blocks precedes includes requires)
  end

  def exactly_one_column_eql_1(columns, prefix = '')
    columns.map { |column| "#{prefix}#{column} = 1" }.join(' XOR ')
  end

  def sum_of_columns(columns, prefix = '')
    columns.map { |column| "#{prefix}#{column}" }.join(' + ')
  end
end
