package com.legendarios.hakuna_connect

import android.nfc.cardemulation.HostApduService
import android.os.Bundle

/**
 * Emula um cartão NFC via Host Card Emulation (HCE).
 *
 * Importante: HCE padrão do Android só emula cartões que conversam por APDU
 * (protocolo ISO-DEP / ISO 14443-4, o mesmo de cartões de aproximação tipo
 * "smart card"). Ele NÃO permite emular o UID/dados brutos de tags MIFARE
 * Classic — isso exigiria hardware NFC específico do fabricante, que não é
 * uma API pública do Android. Ou seja: cartões de controle de acesso
 * baseados em APDU (a maioria dos crachás/credenciais modernos) dá pra
 * emular; cartões MIFARE Classic "de UID fixo" (comuns em portões antigos)
 * geralmente não dá, em nenhum app.
 *
 * O payload de resposta é definido pelo app Flutter via [HceBridge] antes
 * de aproximar o aparelho do leitor (ex: depois de ler/configurar o cartão
 * do Top atual).
 */
class HceService : HostApduService() {

    override fun processCommandApdu(commandApdu: ByteArray?, extras: Bundle?): ByteArray {
        if (commandApdu == null) return STATUS_FAILED

        // Comando SELECT AID -> responde com o payload configurado + status OK.
        if (isSelectAidApdu(commandApdu)) {
            val payload = HceBridge.currentPayload
            return if (payload != null) payload + STATUS_SUCCESS else STATUS_SUCCESS
        }

        // Qualquer outro comando: devolve o payload configurado (se houver) + OK.
        val payload = HceBridge.currentPayload
        return if (payload != null) payload + STATUS_SUCCESS else STATUS_SUCCESS
    }

    override fun onDeactivated(reason: Int) {
        HceBridge.notifyDeactivated(reason)
    }

    private fun isSelectAidApdu(apdu: ByteArray): Boolean {
        // CLA=00 INS=A4 (SELECT) P1=04 (by name/AID)
        return apdu.size >= 4 && apdu[0] == 0x00.toByte() && apdu[1] == 0xA4.toByte() && apdu[2] == 0x04.toByte()
    }

    companion object {
        private val STATUS_SUCCESS = byteArrayOf(0x90.toByte(), 0x00.toByte())
        private val STATUS_FAILED = byteArrayOf(0x6F.toByte(), 0x00.toByte())
    }
}
