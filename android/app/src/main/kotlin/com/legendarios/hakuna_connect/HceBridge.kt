package com.legendarios.hakuna_connect

/**
 * Ponte simples entre o MethodChannel (Flutter) e o [HceService], que roda
 * em processo do sistema e é instanciado pelo Android, não pelo app.
 * Por isso usamos estado estático em vez de injeção normal.
 */
object HceBridge {
    @Volatile
    var currentPayload: ByteArray? = null
        private set

    private var onDeactivatedListener: ((Int) -> Unit)? = null

    fun setPayload(payload: ByteArray?) {
        currentPayload = payload
    }

    fun setOnDeactivatedListener(listener: ((Int) -> Unit)?) {
        onDeactivatedListener = listener
    }

    fun notifyDeactivated(reason: Int) {
        onDeactivatedListener?.invoke(reason)
    }
}
