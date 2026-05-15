package inc.anky.android.core.identity

import java.math.BigInteger

object Base58 {
    private const val Alphabet = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
    private val AlphabetIndex = IntArray(128) { -1 }.also { index ->
        Alphabet.forEachIndexed { i, c -> index[c.code] = i }
    }

    fun encode(input: ByteArray): String {
        if (input.isEmpty()) return ""
        var zeros = 0
        while (zeros < input.size && input[zeros].toInt() == 0) zeros++

        var value = BigInteger(1, input)
        val builder = StringBuilder()
        val base = BigInteger.valueOf(58)
        while (value > BigInteger.ZERO) {
            val divRem = value.divideAndRemainder(base)
            builder.append(Alphabet[divRem[1].toInt()])
            value = divRem[0]
        }
        repeat(zeros) { builder.append(Alphabet[0]) }
        return builder.reverse().toString()
    }

    fun decode(input: String): ByteArray? {
        if (input.isEmpty()) return ByteArray(0)
        var value = BigInteger.ZERO
        val base = BigInteger.valueOf(58)
        for (char in input) {
            if (char.code >= AlphabetIndex.size) return null
            val digit = AlphabetIndex[char.code]
            if (digit < 0) return null
            value = value.multiply(base).add(BigInteger.valueOf(digit.toLong()))
        }
        var bytes = value.toByteArray()
        if (bytes.size > 1 && bytes[0].toInt() == 0) bytes = bytes.copyOfRange(1, bytes.size)
        val zeros = input.takeWhile { it == Alphabet[0] }.length
        return ByteArray(zeros) + bytes
    }
}
