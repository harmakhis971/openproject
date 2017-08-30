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

require 'spec_helper'

describe WorkPackage, type: :model do
  let(:work_package) do
    FactoryGirl.create(:work_package)
  end
  let(:other_work_package) do
    FactoryGirl.create(:work_package)
  end
  let(:child_work_package) do
    wp = FactoryGirl.create(:work_package)

    FactoryGirl.create(:relation,
                       from: work_package,
                       to: wp,
                       relation_type: 'hierarchy',
                       depth: 1)

    wp
  end
  let(:grandchild_work_package) do
    wp = FactoryGirl.create(:work_package)

    FactoryGirl.create(:relation,
                       from: child_work_package,
                       to: wp,
                       relation_type: 'hierarchy',
                       depth: 1)

    # TODO: place generation of closure into production code
    FactoryGirl.create(:relation,
                       from: work_package,
                       to: wp,
                       relation_type: 'hierarchy',
                       depth: 2)

    wp
  end
  let(:parent_work_package) do
    wp = FactoryGirl.create(:work_package)

    FactoryGirl.create(:relation,
                       from: wp,
                       to: work_package,
                       relation_type: 'hierarchy',
                       depth: 1)

    wp
  end
  let(:grandparent_work_package) do
    wp = FactoryGirl.create(:work_package)

    FactoryGirl.create(:relation,
                       from: wp,
                       to: parent_work_package,
                       relation_type: 'hierarchy',
                       depth: 1)

    # TODO: place generation of closure into production code
    FactoryGirl.create(:relation,
                       from: wp,
                       to: work_package,
                       relation_type: 'hierarchy',
                       depth: 2)

    wp
  end

  describe '#leaf?' do
    it 'is true' do
      expect(work_package)
        .to be_leaf
    end

    context 'unpersisted' do
      it 'is true' do
        wp = FactoryGirl.build(:work_package)

        expect(wp)
          .to be_leaf
      end
    end

    context 'with a child' do
      before do
        child_work_package
      end

      it 'is false' do
        expect(work_package)
          .not_to be_leaf
      end
    end
  end

  describe '#children' do
    it 'is empty' do
      expect(work_package.children)
        .to be_empty
    end

    context 'with a child' do
      before do
        child_work_package
      end

      it 'includes the child' do
        expect(work_package.children)
          .to match_array([child_work_package])
      end
    end

    context 'with a grandchild' do
      before do
        child_work_package
        grandchild_work_package
      end

      it 'includes the child' do
        expect(work_package.children)
          .to match_array([child_work_package])
      end
    end
  end

  describe '#descendants' do
    it 'is empty' do
      expect(work_package.descendants)
        .to be_empty
    end

    context 'with a child' do
      before do
        child_work_package
      end

      it 'includes the child' do
        expect(work_package.descendants)
          .to match_array([child_work_package])
      end
    end

    context 'with a grandchild' do
      before do
        child_work_package
        grandchild_work_package
      end

      it 'includes the child and grandchild' do
        expect(work_package.descendants)
          .to match_array([child_work_package, grandchild_work_package])
      end
    end
  end

  describe '#parent' do
    it 'is nil' do
      expect(work_package.parent)
        .to be_nil
    end

    context 'with a parent' do
      before do
        parent_work_package
      end

      it 'returns the parent' do
        expect(work_package.parent)
          .to eql parent_work_package
      end
    end

    context 'with a grandparent' do
      before do
        parent_work_package
        grandparent_work_package
      end

      it 'returns the parent' do
        expect(work_package.parent)
          .to eql parent_work_package
      end
    end
  end

  describe '#ancestors' do
    it 'is empty' do
      expect(work_package.ancestors)
        .to be_empty
    end

    context 'with a parent' do
      before do
        parent_work_package
      end

      it 'includes the parent' do
        expect(work_package.ancestors)
          .to match_array([parent_work_package])
      end
    end

    context 'with a grandparent' do
      before do
        parent_work_package
        grandparent_work_package
      end

      it 'includes the parent and grandparent' do
        expect(work_package.ancestors)
          .to match_array([parent_work_package, grandparent_work_package])
      end
    end
  end

  describe '#in_closure?' do
    it 'is false' do
      expect(work_package.in_closure?(other_work_package))
        .to be_falsey
    end

    context 'with a grandparent' do
      before do
        parent_work_package
        grandparent_work_package
      end

      it 'is true' do
        expect(work_package.in_closure?(grandparent_work_package))
          .to be_truthy
      end
    end

    context 'with a grandchild' do
      before do
        child_work_package
        grandchild_work_package
      end

      it 'is true' do
        expect(work_package.in_closure?(grandchild_work_package))
          .to be_truthy
      end
    end
  end

  describe '#child?' do
    it 'is false' do
      expect(work_package)
        .not_to be_child
    end

    context 'with a parent' do
      before do
        parent_work_package
      end

      it 'is true' do
        expect(work_package)
          .to be_child
      end
    end
  end
end
