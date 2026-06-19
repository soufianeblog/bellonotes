import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import '../providers/app_settings.dart';

/// Simple in-app localization. Each getter returns the string for the current
/// locale, falling back to English when a translation is missing.
///
/// Use `final s = S.of(context);` then `s.newNote`, etc. Widgets that read
/// settings via `context.watch<AppSettings>()` rebuild automatically when the
/// language changes.
class S {
  final String lang;
  const S(this.lang);

  /// Resolves the current language. Safe to call from event handlers: if
  /// called outside the build phase (where `watch` would assert), it falls
  /// back to a non-listening read.
  static S of(BuildContext context) {
    try {
      return S(context.watch<AppSettings>().locale.languageCode);
    } catch (_) {
      return S(context.read<AppSettings>().locale.languageCode);
    }
  }

  static S read(BuildContext context) =>
      S(context.read<AppSettings>().locale.languageCode);

  String _t(Map<String, String> m, String en) => m[lang] ?? en;

  // ─── Navigation ───
  String get appName => 'Bello Notes';
  String get allNotes =>
      _t({'fr': 'Toutes les notes', 'ar': 'كل الملاحظات', 'zh': '所有笔记', 'it': 'Tutte le note', 'es': 'Todas las notas'}, 'All Notes');
  String get folders =>
      _t({'fr': 'Dossiers', 'ar': 'المجلدات', 'zh': '文件夹', 'it': 'Cartelle', 'es': 'Carpetas'}, 'Folders');
  String get trash =>
      _t({'fr': 'Corbeille', 'ar': 'المهملات', 'zh': '回收站', 'it': 'Cestino', 'es': 'Papelera'}, 'Trash');
  String get notes =>
      _t({'fr': 'Notes', 'ar': 'الملاحظات', 'zh': '笔记', 'it': 'Note', 'es': 'Notas'}, 'Notes');
  String get newNote =>
      _t({'fr': 'Nouvelle note', 'ar': 'ملاحظة جديدة', 'zh': '新建笔记', 'it': 'Nuova nota', 'es': 'Nueva nota'}, 'New Note');
  String get newFolder =>
      _t({'fr': 'Nouveau dossier', 'ar': 'مجلد جديد', 'zh': '新建文件夹', 'it': 'Nuova cartella', 'es': 'Nueva carpeta'}, 'New Folder');
  String get createFolder =>
      _t({'fr': 'Créer un dossier', 'ar': 'إنشاء مجلد', 'zh': '创建文件夹', 'it': 'Crea cartella', 'es': 'Crear carpeta'}, 'Create Folder');
  String get searchNotes =>
      _t({'fr': 'Rechercher…', 'ar': 'بحث في الملاحظات…', 'zh': '搜索笔记…', 'it': 'Cerca note…', 'es': 'Buscar notas…'}, 'Search notes...');
  String get settings =>
      _t({'fr': 'Réglages', 'ar': 'الإعدادات', 'zh': '设置', 'it': 'Impostazioni', 'es': 'Ajustes'}, 'Settings');
  String get noteCount =>
      _t({'fr': 'note', 'ar': 'ملاحظة', 'zh': '条笔记', 'it': 'nota', 'es': 'nota'}, 'note');
  String get notesCount =>
      _t({'fr': 'notes', 'ar': 'ملاحظات', 'zh': '条笔记', 'it': 'note', 'es': 'notas'}, 'notes');

  // ─── Date groups ───
  String get pinned =>
      _t({'fr': 'Épinglées', 'ar': 'مثبّتة', 'zh': '已置顶', 'it': 'Fissate', 'es': 'Fijadas'}, 'Pinned');
  String get today =>
      _t({'fr': "Aujourd'hui", 'ar': 'اليوم', 'zh': '今天', 'it': 'Oggi', 'es': 'Hoy'}, 'Today');
  String get yesterday =>
      _t({'fr': 'Hier', 'ar': 'أمس', 'zh': '昨天', 'it': 'Ieri', 'es': 'Ayer'}, 'Yesterday');
  String get previous7 =>
      _t({'fr': '7 derniers jours', 'ar': 'آخر 7 أيام', 'zh': '过去 7 天', 'it': 'Ultimi 7 giorni', 'es': 'Últimos 7 días'}, 'Previous 7 Days');
  String get previous30 =>
      _t({'fr': '30 derniers jours', 'ar': 'آخر 30 يومًا', 'zh': '过去 30 天', 'it': 'Ultimi 30 giorni', 'es': 'Últimos 30 días'}, 'Previous 30 Days');
  String get noNotesFound =>
      _t({'fr': 'Aucune note trouvée', 'ar': 'لا توجد ملاحظات', 'zh': '未找到笔记', 'it': 'Nessuna nota trovata', 'es': 'No se encontraron notas'}, 'No notes found');
  String get trashEmpty =>
      _t({'fr': 'Corbeille vide', 'ar': 'المهملات فارغة', 'zh': '回收站为空', 'it': 'Cestino vuoto', 'es': 'Papelera vacía'}, 'Trash is empty');
  String get noAdditionalText =>
      _t({'fr': 'Aucun texte', 'ar': 'لا نص إضافي', 'zh': '无更多内容', 'it': 'Nessun testo', 'es': 'Sin texto adicional'}, 'No additional text');

  // ─── Common actions ───
  String get cancel =>
      _t({'fr': 'Annuler', 'ar': 'إلغاء', 'zh': '取消', 'it': 'Annulla', 'es': 'Cancelar'}, 'Cancel');
  String get save =>
      _t({'fr': 'Enregistrer', 'ar': 'حفظ', 'zh': '保存', 'it': 'Salva', 'es': 'Guardar'}, 'Save');
  String get delete =>
      _t({'fr': 'Supprimer', 'ar': 'حذف', 'zh': '删除', 'it': 'Elimina', 'es': 'Eliminar'}, 'Delete');
  String get rename =>
      _t({'fr': 'Renommer', 'ar': 'إعادة تسمية', 'zh': '重命名', 'it': 'Rinomina', 'es': 'Renombrar'}, 'Rename');
  String get restore =>
      _t({'fr': 'Restaurer', 'ar': 'استعادة', 'zh': '恢复', 'it': 'Ripristina', 'es': 'Restaurar'}, 'Restore');
  String get restoreAll =>
      _t({'fr': 'Tout restaurer', 'ar': 'استعادة الكل', 'zh': '全部恢复', 'it': 'Ripristina tutto', 'es': 'Restaurar todo'}, 'Restore All');
  String get emptyTrash =>
      _t({'fr': 'Vider la corbeille', 'ar': 'إفراغ المهملات', 'zh': '清空回收站', 'it': 'Svuota cestino', 'es': 'Vaciar papelera'}, 'Empty Trash');
  String get deleteForever =>
      _t({'fr': 'Supprimer définitivement', 'ar': 'حذف نهائي', 'zh': '永久删除', 'it': 'Elimina per sempre', 'es': 'Eliminar para siempre'}, 'Delete Forever');
  String get ok => _t({'fr': 'OK', 'ar': 'موافق', 'zh': '确定', 'it': 'OK', 'es': 'OK'}, 'OK');
  String get done =>
      _t({'fr': 'Terminé', 'ar': 'تم', 'zh': '完成', 'it': 'Fatto', 'es': 'Hecho'}, 'Done');
  String get remove =>
      _t({'fr': 'Retirer', 'ar': 'إزالة', 'zh': '移除', 'it': 'Rimuovi', 'es': 'Quitar'}, 'Remove');
  String get open =>
      _t({'fr': 'Ouvrir', 'ar': 'فتح', 'zh': '打开', 'it': 'Apri', 'es': 'Abrir'}, 'Open');
  String get edit =>
      _t({'fr': 'Modifier', 'ar': 'تعديل', 'zh': '编辑', 'it': 'Modifica', 'es': 'Editar'}, 'Edit');

  // ─── Editor toolbar ───
  String get pin => _t({'fr': 'Épingler', 'ar': 'تثبيت', 'zh': '置顶', 'it': 'Fissa', 'es': 'Fijar'}, 'Pin');
  String get unpin => _t({'fr': 'Détacher', 'ar': 'إلغاء التثبيت', 'zh': '取消置顶', 'it': 'Sblocca', 'es': 'No fijar'}, 'Unpin');
  String get move => _t({'fr': 'Déplacer', 'ar': 'نقل', 'zh': '移动', 'it': 'Sposta', 'es': 'Mover'}, 'Move');
  String get checklist => _t({'fr': 'Liste à cocher', 'ar': 'قائمة مهام', 'zh': '清单', 'it': 'Elenco', 'es': 'Lista'}, 'Checklist');
  String get table => _t({'fr': 'Tableau', 'ar': 'جدول', 'zh': '表格', 'it': 'Tabella', 'es': 'Tabla'}, 'Table');
  String get photo => _t({'fr': 'Photo', 'ar': 'صورة', 'zh': '图片', 'it': 'Foto', 'es': 'Foto'}, 'Photo');
  String get link => _t({'fr': 'Lien', 'ar': 'رابط', 'zh': '链接', 'it': 'Link', 'es': 'Enlace'}, 'Link');
  String get export => _t({'fr': 'Exporter', 'ar': 'تصدير', 'zh': '导出', 'it': 'Esporta', 'es': 'Exportar'}, 'Export');
  String get bold => _t({'fr': 'Gras', 'ar': 'عريض', 'zh': '加粗', 'it': 'Grassetto', 'es': 'Negrita'}, 'Bold');
  String get italic => _t({'fr': 'Italique', 'ar': 'مائل', 'zh': '斜体', 'it': 'Corsivo', 'es': 'Cursiva'}, 'Italic');
  String get underline => _t({'fr': 'Souligné', 'ar': 'تسطير', 'zh': '下划线', 'it': 'Sottolineato', 'es': 'Subrayado'}, 'Underline');
  String get strike => _t({'fr': 'Barré', 'ar': 'يتوسطه خط', 'zh': '删除线', 'it': 'Barrato', 'es': 'Tachado'}, 'Strike');
  String get title => _t({'fr': 'Titre', 'ar': 'عنوان', 'zh': '标题', 'it': 'Titolo', 'es': 'Título'}, 'Title');
  String get heading => _t({'fr': 'En-tête', 'ar': 'ترويسة', 'zh': '小标题', 'it': 'Intestazione', 'es': 'Encabezado'}, 'Heading');
  String get body => _t({'fr': 'Corps', 'ar': 'نص', 'zh': '正文', 'it': 'Corpo', 'es': 'Cuerpo'}, 'Body');
  String get bullets => _t({'fr': 'Puces', 'ar': 'تعداد نقطي', 'zh': '项目符号', 'it': 'Elenco puntato', 'es': 'Viñetas'}, 'Bullets');
  String get numbered => _t({'fr': 'Numéroté', 'ar': 'تعداد رقمي', 'zh': '编号', 'it': 'Numerato', 'es': 'Numerado'}, 'Numbered');
  String get quote => _t({'fr': 'Citation', 'ar': 'اقتباس', 'zh': '引用', 'it': 'Citazione', 'es': 'Cita'}, 'Quote');
  String get codeBlock => _t({'fr': 'Bloc de code', 'ar': 'كتلة برمجية', 'zh': '代码块', 'it': 'Blocco codice', 'es': 'Bloque de código'}, 'Code Block');
  String get markdown => 'Markdown';
  String get visual => _t({'fr': 'Visuel', 'ar': 'مرئي', 'zh': '可视', 'it': 'Visivo', 'es': 'Visual'}, 'Visual');

  String get startWriting => _t({'fr': 'Commencez à écrire…', 'ar': 'ابدأ الكتابة…', 'zh': '开始输入…', 'it': 'Inizia a scrivere…', 'es': 'Empieza a escribir…'}, 'Start writing...');
  String get selectOrCreate => _t({'fr': 'Sélectionnez une note ou créez-en une', 'ar': 'اختر ملاحظة أو أنشئ واحدة', 'zh': '选择或新建一条笔记', 'it': 'Seleziona una nota o creane una', 'es': 'Selecciona una nota o crea una'}, 'Select a note or create a new one');
  String get created => _t({'fr': 'Créé', 'ar': 'أُنشئت', 'zh': '创建于', 'it': 'Creato', 'es': 'Creado'}, 'Created');
  String get modified => _t({'fr': 'Modifié', 'ar': 'عُدّلت', 'zh': '修改于', 'it': 'Modificato', 'es': 'Modificado'}, 'Modified');
  String get chars => _t({'fr': 'caractères', 'ar': 'حرف', 'zh': '字符', 'it': 'caratteri', 'es': 'caracteres'}, 'chars');
  String get words => _t({'fr': 'mots', 'ar': 'كلمة', 'zh': '词', 'it': 'parole', 'es': 'palabras'}, 'words');

  String get assignToFolders => _t({'fr': 'Assigner aux dossiers', 'ar': 'إسناد إلى مجلدات', 'zh': '分配到文件夹', 'it': 'Assegna alle cartelle', 'es': 'Asignar a carpetas'}, 'Assign to Folders');
  String get moveToFolder => _t({'fr': 'Déplacer vers un dossier', 'ar': 'نقل إلى مجلد', 'zh': '移动到文件夹', 'it': 'Sposta nella cartella', 'es': 'Mover a carpeta'}, 'Move to Folder');
  String get linkText => _t({'fr': 'Texte du lien', 'ar': 'نص الرابط', 'zh': '链接文本', 'it': 'Testo del link', 'es': 'Texto del enlace'}, 'Link text');
  String get addLink => _t({'fr': 'Ajouter un lien', 'ar': 'إضافة رابط', 'zh': '添加链接', 'it': 'Aggiungi link', 'es': 'Añadir enlace'}, 'Add Link');
  String get editLink => _t({'fr': 'Modifier le lien', 'ar': 'تعديل الرابط', 'zh': '编辑链接', 'it': 'Modifica link', 'es': 'Editar enlace'}, 'Edit Link');

  // ─── Settings ───
  String get appearance => _t({'fr': 'Apparence', 'ar': 'المظهر', 'zh': '外观', 'it': 'Aspetto', 'es': 'Apariencia'}, 'Appearance');
  String get theme => _t({'fr': 'Thème', 'ar': 'السمة', 'zh': '主题', 'it': 'Tema', 'es': 'Tema'}, 'Theme');
  String get language => _t({'fr': 'Langue', 'ar': 'اللغة', 'zh': '语言', 'it': 'Lingua', 'es': 'Idioma'}, 'Language');
  String get auto => _t({'fr': 'Auto', 'ar': 'تلقائي', 'zh': '自动', 'it': 'Auto', 'es': 'Auto'}, 'Auto');
  String get light => _t({'fr': 'Clair', 'ar': 'فاتح', 'zh': '浅色', 'it': 'Chiaro', 'es': 'Claro'}, 'Light');
  String get dark => _t({'fr': 'Sombre', 'ar': 'داكن', 'zh': '深色', 'it': 'Scuro', 'es': 'Oscuro'}, 'Dark');
  String get editor => _t({'fr': 'Éditeur', 'ar': 'المحرر', 'zh': '编辑器', 'it': 'Editor', 'es': 'Editor'}, 'Editor');
  String get newNotesStartWith => _t({'fr': 'Les nouvelles notes commencent par', 'ar': 'تبدأ الملاحظات الجديدة بـ', 'zh': '新笔记的起始格式', 'it': 'Le nuove note iniziano con', 'es': 'Las notas nuevas empiezan con'}, 'New notes start with');
  String get defaultTextSize => _t({'fr': 'Taille du texte par défaut', 'ar': 'حجم النص الافتراضي', 'zh': '默认文字大小', 'it': 'Dimensione testo predefinita', 'es': 'Tamaño de texto predeterminado'}, 'Default text size');
  String get darkEditorBg => _t({'fr': "Fond d'éditeur sombre", 'ar': 'خلفية محرر داكنة', 'zh': '深色编辑器背景', 'it': 'Sfondo editor scuro', 'es': 'Fondo de editor oscuro'}, 'Dark editor background');
  String get sorting => _t({'fr': 'Tri', 'ar': 'الترتيب', 'zh': '排序', 'it': 'Ordinamento', 'es': 'Orden'}, 'Sorting');
  String get security => _t({'fr': 'Sécurité', 'ar': 'الأمان', 'zh': '安全', 'it': 'Sicurezza', 'es': 'Seguridad'}, 'Security');
  String get lockPassword => _t({'fr': 'Mot de passe de verrouillage', 'ar': 'كلمة مرور القفل', 'zh': '锁定密码', 'it': 'Password di blocco', 'es': 'Contraseña de bloqueo'}, 'Lock password');
  String get data => _t({'fr': 'Données', 'ar': 'البيانات', 'zh': '数据', 'it': 'Dati', 'es': 'Datos'}, 'Data');
  String get exportAllData => _t({'fr': 'Exporter toutes les données', 'ar': 'تصدير كل البيانات', 'zh': '导出所有数据', 'it': 'Esporta tutti i dati', 'es': 'Exportar todos los datos'}, 'Export all data');
  String get importData => _t({'fr': 'Importer des données', 'ar': 'استيراد البيانات', 'zh': '导入数据', 'it': 'Importa dati', 'es': 'Importar datos'}, 'Import data');
  String get exportImportSubtitle => _t({'fr': 'Archive .zip (notes, dossiers, images)', 'ar': 'أرشيف .zip (ملاحظات، مجلدات، صور)', 'zh': '.zip 归档（笔记、文件夹、图片）', 'it': 'Archivio .zip (note, cartelle, immagini)', 'es': 'Archivo .zip (notas, carpetas, imágenes)'}, '.zip archive (notes, folders, images)');
  String get diagnostics => _t({'fr': 'Diagnostics', 'ar': 'التشخيص', 'zh': '诊断', 'it': 'Diagnostica', 'es': 'Diagnóstico'}, 'Diagnostics');
  String get errorLog => _t({'fr': "Journal d'erreurs", 'ar': 'سجل الأخطاء', 'zh': '错误日志', 'it': 'Registro errori', 'es': 'Registro de errores'}, 'Error log');
  String get about => _t({'fr': 'À propos', 'ar': 'حول', 'zh': '关于', 'it': 'Informazioni', 'es': 'Acerca de'}, 'About');

  // ─── About page ───
  String get version => _t({'fr': 'Version', 'ar': 'الإصدار', 'zh': '版本', 'it': 'Versione', 'es': 'Versión'}, 'Version');
  String get madeBy => _t({'fr': 'Créé par', 'ar': 'صنعه', 'zh': '作者', 'it': 'Creato da', 'es': 'Creado por'}, 'Made by');
  String get website => _t({'fr': 'Site web', 'ar': 'الموقع', 'zh': '网站', 'it': 'Sito web', 'es': 'Sitio web'}, 'Website');
  String get sourceCode => _t({'fr': 'Code source', 'ar': 'الكود المصدري', 'zh': '源代码', 'it': 'Codice sorgente', 'es': 'Código fuente'}, 'Source code');
  String get aboutTagline => _t({'fr': 'Notes open source, multiplateformes.', 'ar': 'ملاحظات مفتوحة المصدر، متعددة المنصات.', 'zh': '开源、跨平台的笔记应用。', 'it': 'Note open source, multipiattaforma.', 'es': 'Notas de código abierto, multiplataforma.'}, 'Open-source, cross-platform notes.');

  // ─── Folder delete / trash / multi-select ───
  String get moveNotesToAllNotes => _t({'fr': 'Déplacer les notes vers Toutes les notes', 'ar': 'نقل الملاحظات إلى كل الملاحظات', 'zh': '将笔记移至所有笔记', 'it': 'Sposta le note in Tutte le note', 'es': 'Mover notas a Todas las notas'}, 'Move notes to All Notes');
  String get notesKeptInAllNotes => _t({'fr': 'Les notes restent dans Toutes les notes', 'ar': 'تبقى الملاحظات في كل الملاحظات', 'zh': '笔记保留在所有笔记中', 'it': 'Le note restano in Tutte le note', 'es': 'Las notas permanecen en Todas las notas'}, 'Notes stay in All Notes');
  String get notesSentToTrash => _t({'fr': 'Les notes iront aussi à la corbeille', 'ar': 'سيتم نقل الملاحظات إلى المهملات أيضًا', 'zh': '笔记也将被移至回收站', 'it': 'Anche le note andranno nel cestino', 'es': 'Las notas también irán a la papelera'}, 'Notes will also be moved to Trash');
  String get selected => _t({'fr': 'sélectionné(s)', 'ar': 'محدد', 'zh': '已选择', 'it': 'selezionati', 'es': 'seleccionados'}, 'selected');
  String get selectItems => _t({'fr': 'Sélectionner', 'ar': 'تحديد', 'zh': '选择', 'it': 'Seleziona', 'es': 'Seleccionar'}, 'Select');
  String get recentlyDeleted => _t({'fr': 'Récemment supprimés', 'ar': 'المحذوفة مؤخرًا', 'zh': '最近删除', 'it': 'Eliminati di recente', 'es': 'Eliminados recientemente'}, 'Recently Deleted');

  // ─── Editor: colors, alignment, font, size ───
  String get textColor => _t({'fr': 'Couleur du texte', 'ar': 'لون النص', 'zh': '文字颜色', 'it': 'Colore testo', 'es': 'Color de texto'}, 'Text color');
  String get highlight => _t({'fr': 'Surlignage', 'ar': 'تظليل', 'zh': '高亮', 'it': 'Evidenzia', 'es': 'Resaltar'}, 'Highlight');
  String get alignLeft => _t({'fr': 'Aligner à gauche', 'ar': 'محاذاة لليسار', 'zh': '左对齐', 'it': 'Allinea a sinistra', 'es': 'Alinear a la izquierda'}, 'Align left');
  String get alignCenter => _t({'fr': 'Centrer', 'ar': 'توسيط', 'zh': '居中', 'it': 'Centra', 'es': 'Centrar'}, 'Align center');
  String get alignRight => _t({'fr': 'Aligner à droite', 'ar': 'محاذاة لليمين', 'zh': '右对齐', 'it': 'Allinea a destra', 'es': 'Alinear a la derecha'}, 'Align right');
  String get alignJustify => _t({'fr': 'Justifier', 'ar': 'ضبط', 'zh': '两端对齐', 'it': 'Giustifica', 'es': 'Justificar'}, 'Justify');
  String get font => _t({'fr': 'Police', 'ar': 'الخط', 'zh': '字体', 'it': 'Carattere', 'es': 'Fuente'}, 'Font');
  String get size => _t({'fr': 'Taille', 'ar': 'الحجم', 'zh': '字号', 'it': 'Dimensione', 'es': 'Tamaño'}, 'Size');
  String get custom => _t({'fr': 'Personnalisé', 'ar': 'مخصص', 'zh': '自定义', 'it': 'Personalizzato', 'es': 'Personalizado'}, 'Custom');
  String get defaultFont => _t({'fr': 'Par défaut', 'ar': 'افتراضي', 'zh': '默认', 'it': 'Predefinito', 'es': 'Predeterminado'}, 'Default');
  String get noColor => _t({'fr': 'Aucune', 'ar': 'بلا', 'zh': '无', 'it': 'Nessuno', 'es': 'Ninguno'}, 'None');

  // ─── Editor: table & image ───
  String get row => _t({'fr': 'Ligne', 'ar': 'صف', 'zh': '行', 'it': 'Riga', 'es': 'Fila'}, 'Row');
  String get col => _t({'fr': 'Col', 'ar': 'عمود', 'zh': '列', 'it': 'Col', 'es': 'Col'}, 'Col');
  String get insertTable => _t({'fr': 'Insérer un tableau', 'ar': 'إدراج جدول', 'zh': '插入表格', 'it': 'Inserisci tabella', 'es': 'Insertar tabla'}, 'Insert table');
  String get deleteRow => _t({'fr': 'Supprimer la ligne', 'ar': 'حذف الصف', 'zh': '删除行', 'it': 'Elimina riga', 'es': 'Eliminar fila'}, 'Delete row');
  String get deleteColumn => _t({'fr': 'Supprimer la colonne', 'ar': 'حذف العمود', 'zh': '删除列', 'it': 'Elimina colonna', 'es': 'Eliminar columna'}, 'Delete column');
  String get cellColor => _t({'fr': 'Couleur de cellule', 'ar': 'لون الخلية', 'zh': '单元格颜色', 'it': 'Colore cella', 'es': 'Color de celda'}, 'Cell color');
  String get deleteTable => _t({'fr': 'Supprimer le tableau', 'ar': 'حذف الجدول', 'zh': '删除表格', 'it': 'Elimina tabella', 'es': 'Eliminar tabla'}, 'Delete table');
  String get border => _t({'fr': 'Bordure', 'ar': 'الحدود', 'zh': '边框', 'it': 'Bordo', 'es': 'Borde'}, 'Border');
  String get resize => _t({'fr': 'Redimensionner', 'ar': 'تغيير الحجم', 'zh': '调整大小', 'it': 'Ridimensiona', 'es': 'Redimensionar'}, 'Resize');
  String get small => _t({'fr': 'Petit', 'ar': 'صغير', 'zh': '小', 'it': 'Piccolo', 'es': 'Pequeño'}, 'Small');
  String get medium => _t({'fr': 'Moyen', 'ar': 'متوسط', 'zh': '中', 'it': 'Medio', 'es': 'Mediano'}, 'Medium');
  String get large => _t({'fr': 'Grand', 'ar': 'كبير', 'zh': '大', 'it': 'Grande', 'es': 'Grande'}, 'Large');
  String get fullWidth => _t({'fr': 'Pleine largeur', 'ar': 'عرض كامل', 'zh': '满宽', 'it': 'Larghezza piena', 'es': 'Ancho completo'}, 'Full width');
  String get removeLink => _t({'fr': 'Supprimer le lien', 'ar': 'إزالة الرابط', 'zh': '移除链接', 'it': 'Rimuovi link', 'es': 'Quitar enlace'}, 'Remove link');
  String get themeColor => _t({'fr': "Couleur du thème", 'ar': 'لون السمة', 'zh': '主题色', 'it': 'Colore tema', 'es': 'Color del tema'}, 'Theme color');
  String get exportLogs => _t({'fr': 'Exporter les journaux', 'ar': 'تصدير السجلات', 'zh': '导出日志', 'it': 'Esporta registri', 'es': 'Exportar registros'}, 'Export logs');
}
