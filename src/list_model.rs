// SPDX-FileCopyrightText: 2025-2026 Uncore <https://github.com/uncor3>
// SPDX-License-Identifier: AGPL-3.0-or-later

use qmetaobject::{
    QAbstractListModel, QByteArray, QModelIndex, QObject, QObjectCppWrapper, QVariant,
    SimpleListItem, USER_ROLE,
};
use std::collections::HashMap;
use std::iter::FromIterator;
use std::ops::Index;

/// SimpleListModel with mutate support
/// avoids clonning
#[derive(QObject, Default)]
pub struct ListModel<T: SimpleListItem + 'static> {
    #[qt_base_class = "QAbstractListModel"]
    base: QObjectCppWrapper,
    pub values: Vec<T>,
}

impl<T: SimpleListItem> QAbstractListModel for ListModel<T> {
    fn row_count(&self) -> i32 {
        self.values.len() as i32
    }

    fn data(&self, index: QModelIndex, role: i32) -> QVariant {
        let idx = index.row();
        if idx >= 0 && (idx as usize) < self.values.len() {
            self.values[idx as usize].get(role - USER_ROLE).clone()
        } else {
            QVariant::default()
        }
    }

    fn role_names(&self) -> HashMap<i32, QByteArray> {
        T::names()
            .iter()
            .enumerate()
            .map(|(i, x)| (i as i32 + USER_ROLE, x.clone()))
            .collect()
    }
}

impl<T: SimpleListItem> ListModel<T> {
    pub fn insert(&mut self, index: usize, element: T) {
        (self as &mut dyn QAbstractListModel).begin_insert_rows(index as i32, index as i32);
        self.values.insert(index, element);
        (self as &mut dyn QAbstractListModel).end_insert_rows();
    }

    pub fn push(&mut self, value: T) {
        let idx = self.values.len();
        self.insert(idx, value);
    }

    pub fn remove(&mut self, index: usize) {
        (self as &mut dyn QAbstractListModel).begin_remove_rows(index as i32, index as i32);
        self.values.remove(index);
        (self as &mut dyn QAbstractListModel).end_remove_rows();
    }

    pub fn change_line(&mut self, index: usize, value: T) {
        self.values[index] = value;
        let idx = (self as &mut dyn QAbstractListModel).row_index(index as i32);
        (self as &mut dyn QAbstractListModel).data_changed(idx, idx);
    }

    pub fn reset_data(&mut self, data: Vec<T>) {
        (self as &mut dyn QAbstractListModel).begin_reset_model();
        self.values = data;
        (self as &mut dyn QAbstractListModel).end_reset_model();
    }

    pub fn iter(&self) -> impl Iterator<Item = &T> {
        self.values.iter()
    }

    // avoid clonning
    pub fn mutate<F: FnOnce(&mut T) -> R, R>(&mut self, index: usize, f: F) -> Option<R> {
        if index >= self.values.len() {
            return None;
        }
        let result = f(&mut self.values[index]);
        let idx = (self as &mut dyn QAbstractListModel).row_index(index as i32);
        (self as &mut dyn QAbstractListModel).data_changed(idx, idx);
        Some(result)
    }

    pub fn mutate_range<F: FnMut(usize, &mut T)>(
        &mut self,
        range: std::ops::Range<usize>,
        mut f: F,
    ) {
        let len = self.values.len();
        let start = range.start.min(len);
        let end = range.end.min(len);
        if start >= end {
            return;
        }
        for i in start..end {
            f(i, &mut self.values[i]);
        }
        let top = (self as &mut dyn QAbstractListModel).row_index(start as i32);
        let bottom = (self as &mut dyn QAbstractListModel).row_index((end - 1) as i32);
        (self as &mut dyn QAbstractListModel).data_changed(top, bottom);
    }
}

impl<T: SimpleListItem> Index<usize> for ListModel<T> {
    type Output = T;
    fn index(&self, index: usize) -> &T {
        &self.values[index]
    }
}

impl<T: SimpleListItem + Default> FromIterator<T> for ListModel<T> {
    fn from_iter<I: IntoIterator<Item = T>>(iter: I) -> ListModel<T> {
        let mut m = ListModel::default();
        m.values = Vec::from_iter(iter);
        m
    }
}
