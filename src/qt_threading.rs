// SPDX-FileCopyrightText: 2025-2026 Uncore <https://github.com/uncor3>
// SPDX-License-Identifier: AGPL-3.0-or-later

use qmetaobject::prelude::*;
use std::sync::Arc;

struct SendableQPointer<T: QObject + 'static>(QPointer<T>);

// https://doc.qt.io/qt-6/qmetaobject.html
// Only used in the main thread should be safe?
unsafe impl<T: QObject + 'static> Send for SendableQPointer<T> {}
unsafe impl<T: QObject + 'static> Sync for SendableQPointer<T> {}

type Job<T> = Box<dyn FnOnce(&mut T) + Send + 'static>;

pub struct QtThread<T: QObject + 'static> {
    invoke: Arc<dyn Fn(Job<T>) + Send + Sync + 'static>,
}

impl<T: QObject + 'static> Clone for QtThread<T> {
    fn clone(&self) -> Self {
        Self {
            invoke: self.invoke.clone(),
        }
    }
}

impl<T: QObject + 'static> QtThread<T> {
    pub fn new(obj: &T) -> Self {
        let ptr = SendableQPointer(QPointer::from(obj));

        let cb = qmetaobject::queued_callback(move |job: Job<T>| {
            if let Some(obj) = ptr.0.as_pinned() {
                let mut obj = obj.borrow_mut();
                job(&mut obj);
            } else {
                eprintln!("QtThread::queue: QObject is gone (QPointer is null)");
            }
        });

        Self {
            invoke: Arc::new(move |job: Job<T>| cb(job)),
        }
    }

    pub fn queue<F>(&self, f: F)
    where
        F: FnOnce(&mut T) + Send + 'static,
    {
        (self.invoke)(Box::new(f));
    }
}

pub trait QtThreading: QObject + 'static {
    fn qt_thread(&self) -> QtThread<Self>
    where
        Self: Sized;
}
