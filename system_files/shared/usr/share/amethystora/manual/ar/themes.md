# السمات

السمة لوحة ألوان واحدة، يُلوَّن منها كل شيء. بدّل السمة فيتغيّر سطح المكتب كله معًا: النمط الفاتح أو
الداكن في GNOME ولون التمييز، والطرفية، ومحث الصدفة، والشريط العلوي، والمرسى، والخلفية، وVSCodium،
وهذا الدليل. وتمنح السمة الفاتحة المرسى مسحة داكنة خفيفة، كي تظل أيقوناته بارزة على خلفية شاحبة.

## التبديل

| المفتاح | ما يفعله |
| --- | --- |
| `Super+Ctrl+Shift+Space` | اختر سمة |
| `Super+Ctrl+D` | بدّل بين النسختين الفاتحة والداكنة من السمة |
| `Super+Ctrl+Space` | الخلفية التالية من السمة الحالية |

والأمر نفسه من الطرفية:

```bash
ame desktop theme                   # pick one from a list
amethystora-theme list              # the themes, with the current one marked
amethystora-theme set "Tokyo Night" # apply one by name
amethystora-theme toggle            # light or dark
amethystora-theme current           # which one is on
```

## السمات المتاحة

| السمة | الاسم المستخدم | النمط |
| --- | --- | --- |
| Amethystora | `amethystora` | داكنة، وهي المبدئية |
| Amethystora Light | `amethystora-light` | فاتحة |
| Catppuccin Mocha | `catppuccin` | داكنة |
| Catppuccin Latte | `catppuccin-latte` | فاتحة |
| Everforest | `everforest` | داكنة |
| Gruvbox | `gruvbox` | داكنة |
| Matte Black | `matte-black` | داكنة |
| Nord | `nord` | داكنة |
| Rosé Pine Dawn | `rose-pine-dawn` | فاتحة |
| Tokyo Night | `tokyo-night` | داكنة |

تجلب سمتا Amethystora أيضًا سمة GTK الخاصة بـAmethystora، وهي التي فيها الأضواء الملونة الثلاثة في زاوية
كل نافذة. أما السمات الأخرى فتُبقي على مظهر GNOME الأصلي بلون تمييزها. يبدّل `Super+Ctrl+D` السمة إلى
شريكتها (Catppuccin Mocha وLatte، وAmethystora وAmethystora Light)؛ والسمة التي لا شريكة لها تتحول إلى
Amethystora في الوضع الآخر.

## الخلفيات

تأتي كل سمة بثلاث خلفيات لأماكن متخيَّلة مرسومة بألوانها، والانتقال إلى سمة يضع أولى خلفياتها على سطح
المكتب: مدينة نيون تحت المطر لـTokyo Night، وشفق قطبي فوق بحيرة جبلية لـNord، وأشجار صنوبر يلفّها الضباب
لـEverforest، وغروب في الصحراء لـGruvbox، وقمم تحت قمر بألوان هادئة لـCatppuccin، وكسوف لـMatte Black،
وهكذا. يتنقّل `Super+Ctrl+Space` بينها. وتبدأ سمتا Amethystora بأوجه حجر مصقول، وفيهما أيضًا حقل
البلورات وسماء ليلية من دخان بنفسجي؛ وتعرضهما إعدادات GNOME تحت المظهر.

لإضافة صورك، ضعها (JPG أو PNG أو WebP أو SVG) في مجلد يحمل اسم السمة، فتأتي بعد صور السمة نفسها:

```bash
mkdir -p ~/.config/amethystora/backgrounds/amethystora
cp ~/Pictures/mountains.jpg ~/.config/amethystora/backgrounds/amethystora/
```

يعرض `amethystora-theme bg list` ما لدى السمة الحالية للتنقّل بينه، ويعيّن
`amethystora-theme bg set <picture>` إحداها مباشرة.

## الانتقالات

لا تظهر السمة أو الخلفية الجديدة ظهورًا عاديًا. تثبت الشاشة لحظة بينما يتغيّر كل شيء تحتها، ثم ينفتح
سطح المكتب الجديد في دائرة تتسع من المؤشر، يحفّ حافتها توهّج بلون تمييز السمة. ويجري الأمر بالطريقة
نفسها أيًّا كانت وسيلة التغيير: المفاتيح أعلاه، أو إعدادات GNOME، أو زر النمط الداكن في الإعدادات
السريعة.

```bash
ame desktop transition         # pick one from a list
ame desktop transition wave    # or name it
```

| الانتقال | شكله |
| --- | --- |
| `grow` | دائرة تتسع من المؤشر. وهو المبدئي |
| `outer` | سطح المكتب الجديد ينغلق من الحواف نحو المؤشر |
| `wipe` | حافة ناعمة تمسح الشاشة بزاوية مائلة |
| `wave` | الأمر نفسه، بحافة متموّجة |
| `fade` | تلاشٍ متقاطع بسيط |
| `random` | واحد من الأربعة الأولى، بأي زاوية |
| `none` | بلا حركة: تتلاشى الخلفية كما يُلاشيها GNOME |

يستغرق الانتقال 1.2 ثانية. لتغيير ذلك، حدّد المدة بالميلي ثانية:

```bash
gsettings set org.gnome.shell.extensions.amethystora-transitions duration 800
```

لا تحدث الانتقالات ما دامت الحركات معطّلة في الإعدادات، تحت الإتاحة. وهي تأتي من امتداد Amethystora
Transitions، الذي يستطيع مدير الامتدادات تعطيله.

## الأيقونات

الأيقونات من candy-icons، وهي المجموعة نفسها في كل سمة: مجلداتها، وأنواع ملفاتها، ورموزها المتدرجة
الألوان للتطبيقات التي تؤدي مهمة بسيطة، مثل الملفات أو الإعدادات أو الحاسبة. أما التطبيق الذي له شعاره
الخاص فيحتفظ به. فـFirefox وThunderbird وبيئات JetBrains التطويرية ومعظم ما تثبّته تُظهر الأيقونة التي
رسمها صانعها، لا أيقونة معاد رسمها: فالشعار علامة تجارية، وشكله قرار مالكه. ولهذا يمزج المرسى بين
النمطين.

## عدّل سمة، أو اصنع سمتك

تأتي السمات للقراءة فقط في `/usr/share/amethystora/themes`. والمجلد الذي يحمل الاسم نفسه في
`~/.config/amethystora/themes` يُوضع فوقها، فلا تكتب إلا الملفات التي تريد تغييرها. والمجلد الذي يحمل
اسمًا خاصًا به سمة جديدة. كل ملف صغير واختياري، باستثناء لوحة الألوان:

| الملف | محتواه |
| --- | --- |
| `colors.toml` | لوحة الألوان: `accent` و`foreground` و`background` و`cursor` و`selection_foreground` و`selection_background`، و`color0` إلى `color15` |
| `light.mode` | موجود، وفارغ، حين تكون السمة فاتحة |
| `pair.theme` | السمة التي يبدّل إليها `Super+Ctrl+D` |
| `accent.theme` | لون التمييز في GNOME: blue أو teal أو green أو yellow أو orange أو red أو pink أو purple أو slate. ومن دونه يُختار أقرب لون |
| `gtk.theme` | اسم سمة GTK، بدلًا من مظهر GNOME الأصلي |
| `icons.theme` | سمة أيقونات، بدلًا من candy-icons |
| `cursor.theme` | سمة مؤشر |
| `vscode.theme` | سمة ألوان VSCodium التي يُبدَّل إليها |
| `tophat.theme` | لون مقاييس الشريط العلوي، حين لا يظهر لون التمييز جيدًا في خط رفيع |
| `backgrounds/` | الخلفيات |
| `backgrounds.list` | خلفيات محفوظة في مكان آخر من النظام، مسار في كل سطر. الأولى هي التي تبدأ بها السمة |

السمة التي ليس لها صور خاصة تحصل على أربع صور مرسومة بألوانها: توهّج ناعم، وتلال في ضباب، وخريطة
كنتورية، وأشرطة منسابة.

تحتاج سمتك الخاصة إلى ثلاثة أوامر:

```bash
mkdir -p ~/.config/amethystora/themes/sunset
cp /usr/share/amethystora/themes/amethystora/colors.toml ~/.config/amethystora/themes/sunset/
amethystora-theme set sunset
```

عدّل الألوان، ونفّذ `amethystora-theme set sunset` مجددًا، وانظر إلى النتيجة.

## للتعمّق أكثر

- **كيف تُكتب الإعدادات.** لوحة ألوان الطرفية، والمحث، وألوان btop، والخلفيات المرسومة كلها قوالب في
  `/usr/share/amethystora/themed`. انسخ أحدها إلى `~/.config/amethystora/themed/` وعدّل النسخة لتغيّر
  طريقة إخراج كل السمات له.
- **شغّل شيئًا عند كل تبديل.** ضع ملفًا تنفيذيًا في `~/.config/amethystora/hooks/theme-set.d/`. وسيتلقى
  اسم السمة في `AMETHYSTORA_THEME` ومجلدها في `AMETHYSTORA_THEME_DIR`.
- **محثّك الخاص يبقى لك.** إن كنت كتبت `~/.config/starship.toml` بنفسك، فلن تمسّه السمة.
- **لا تعدّل `~/.config/amethystora/current/` أبدًا.** فهو يُعاد كتابته عند كل تبديل.

## قائمة الإقلاع

يمكن لقائمة الإقلاع أن تحمل رسومات Amethystora أيضًا. وهذا معطّل مبدئيًا، لأن قائمة الإقلاع تقع خارج
الصورة:

```bash
ame desktop boot-menu
```

نفّذه مجددًا لإزالة الرسومات. وما إن تُفعَّل، حتى تُبقيها تحديثات الصورة محدَّثة.
