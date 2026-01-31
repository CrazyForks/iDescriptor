/*
 * iDescriptor: A free and open-source idevice management tool.
 *
 * Copyright (C) 2025 Uncore <https://github.com/uncor3>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as published
 * by the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

#include "diagnosedialog.h"
#include "iDescriptor-ui.h"
#include <QApplication>

DiagnoseDialog::DiagnoseDialog(QWidget *parent) : QDialog(parent)
{
    setupUI();
    setWindowTitle("System Dependencies");
    setModal(true);
    setAttribute(Qt::WA_DeleteOnClose, true);
}

void DiagnoseDialog::setupUI()
{
    setMinimumSize(MIN_MAIN_WINDOW_SIZE.width(), MIN_MAIN_WINDOW_SIZE.height() / 2);
    QVBoxLayout *mainLayout = new QVBoxLayout(this);
    mainLayout->setContentsMargins(10, 10, 10, 10);

    /*
        TODO: either subclass DiagnoseWidget or
        modify its layout to better fit dialog
    */
    m_diagnoseWidget = new DiagnoseWidget();

    QHBoxLayout *buttonLayout = new QHBoxLayout();
    buttonLayout->addStretch();

    m_closeButton = new QPushButton("Close");
    m_closeButton->setMinimumWidth(80);
    connect(m_closeButton, &QPushButton::clicked, this,
            &DiagnoseDialog::onCloseClicked);

    buttonLayout->addWidget(m_closeButton);

    mainLayout->addWidget(m_diagnoseWidget);
    mainLayout->addLayout(buttonLayout);
}

void DiagnoseDialog::onCloseClicked() { accept(); }