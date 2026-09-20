package no.osilion.agentkhata

import android.appwidget.AppWidgetManager
import android.content.Context
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import android.content.SharedPreferences

/**
 * The counter's numbers on the launcher.
 *
 * ## Why the strings arrive pre-formatted
 *
 * Every visible string — the labels, the taka amounts, the Bangla numerals — is
 * written by the Dart side into the shared preferences this provider reads. The
 * launcher process has no access to the app's locale choice, its currency
 * grouping (12,34,567 rather than 1,234,567) or its Bangla digit mapping, and
 * reimplementing those here would guarantee two formatters that disagree. This
 * class does layout and taps, nothing else.
 *
 * ## Why it never reads the database
 *
 * An AppWidgetProvider runs in a broadcast receiver with roughly ten seconds
 * and no Flutter engine. Opening a Drift database and summing a ledger there
 * would be slow at best and an ANR at worst. The numbers are already computed
 * by the app that owns them; this only paints the last ones it published.
 */
class HomeScreenWidget : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        for (widgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.agentkhata_widget)

            views.setTextViewText(R.id.widget_shop, widgetData.text("shop", context.getString(R.string.widget_title)))
            views.setTextViewText(R.id.widget_updated, widgetData.text("updated", ""))
            views.setTextViewText(R.id.widget_float_label, widgetData.text("floatLabel", "Float"))
            views.setTextViewText(R.id.widget_float, widgetData.text("float", "—"))
            views.setTextViewText(R.id.widget_cash_label, widgetData.text("cashLabel", "Cash"))
            views.setTextViewText(R.id.widget_cash, widgetData.text("cash", "—"))
            views.setTextViewText(R.id.widget_today, widgetData.text("today", ""))
            views.setTextViewText(R.id.widget_add, widgetData.text("addLabel", "+"))
            views.setTextViewText(R.id.widget_inbox, widgetData.text("inboxLabel", ""))

            /*
             * The alert line is the only conditional row. A low-float warning
             * that is always present is wallpaper; one that appears only when
             * the wallet is actually draining is a warning.
             */
            val alert = widgetData.text("alert", "")
            views.setTextViewText(R.id.widget_alert, alert)
            views.setViewVisibility(R.id.widget_alert, if (alert.isEmpty()) View.GONE else View.VISIBLE)

            // Tapping the body opens the dashboard; the two buttons deep-link
            // to the screens the agent actually came for.
            views.setOnClickPendingIntent(
                R.id.widget_shop,
                HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse("agentkhata://widget/home")),
            )
            views.setOnClickPendingIntent(
                R.id.widget_add,
                HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse("agentkhata://widget/add")),
            )
            views.setOnClickPendingIntent(
                R.id.widget_inbox,
                HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse("agentkhata://widget/unsorted")),
            )

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}

/** Missing and empty are the same thing to a layout, so collapse them here. */
private fun SharedPreferences.text(key: String, fallback: String): String {
    val value = getString(key, null)
    return if (value.isNullOrEmpty()) fallback else value
}
