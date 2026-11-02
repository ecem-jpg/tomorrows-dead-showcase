class_name BodyView
extends RefCounted
## Morgda gerçekten görünen bir cesedin arayüze verilebilir görünümü (K-029). İç durum adlarını, varış
## koşullarını ve gelecekteki görünümleri içermez. Kaybolan (ölümü engellenen) cesetler için oluşturulmaz.
## Her çağrıda yeni oluşturulur; değiştirilmesi durumu etkilemez.

## Ölüm ihtimali beklemede.
const PRESENCE_PRESENT: StringName = &"present"
## Ölüm kalıcı hâle geldi.
const PRESENCE_PERMANENT: StringName = &"permanent"

var occurrence_id: StringName = &""
var subject_id: StringName = &""
var night: int = 0
var presence: StringName = &""
