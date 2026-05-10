#include <QInputDialog>
#include <QString>

QString qinput_get_text(bool ok)
{
    return QInputDialog::getText(
        nullptr, "SSH Root Password",
        "Enter the root password: \n(leave empty if you "
        "want to use the default)",
        QLineEdit::Normal, QString(), &ok);
}