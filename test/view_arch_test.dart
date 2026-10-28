import 'package:flutter_test/flutter_test.dart';

import 'package:odoo_mobileapp/odoo/view_arch.dart';

void main() {
  test('parseCardFields skips hidden and optional-hide columns', () {
    const arch = '''
<list create="0">
  <field name="sequence" widget="handle"/>
  <field name="name"/>
  <field name="partner_id"/>
  <field name="company_id" column_invisible="1"/>
  <field name="note" optional="hide"/>
  <field name="amount_total" sum="Total"/>
  <field name="state" widget="badge"/>
</list>''';
    expect(parseCardFields(arch).map((f) => f.name), ['name', 'partner_id', 'amount_total', 'state']);
    expect(archAllows(arch, 'create'), isFalse);
    expect(archAllows(arch, 'delete'), isTrue);
  });

  test('parseSearchFilters keeps domain filters with their groups', () {
    const arch = '''
<search>
  <field name="name"/>
  <filter name="my" string="My Orders" domain="[('user_id', '=', uid)]"/>
  <separator/>
  <filter name="draft" string="Quotations" domain="[('state', '=', 'draft')]"/>
  <filter name="sale" string="Orders" domain="[('state', '=', 'sale')]"/>
  <filter name="order_date" date="date_order"/>
  <group expand="0">
    <filter name="by_customer" string="Customer" context="{'group_by': 'partner_id'}"/>
  </group>
</search>''';
    final filters = parseSearchFilters(arch);
    expect(filters.map((f) => f.name), ['my', 'draft', 'sale']);
    expect(filters[0].group, isNot(filters[1].group));
    expect(filters[1].group, filters[2].group);
  });

  test('parseFormArch reads header, title, groups and pages', () {
    const arch = '''
<form delete="false">
  <header>
    <button name="action_confirm" type="object" string="Confirm" class="oe_highlight" invisible="state != 'draft'"/>
    <button name="%(42)d" type="action" string="Send"/>
    <button name="hidden" type="object" string="Hidden" invisible="1"/>
    <field name="state" widget="statusbar" statusbar_visible="draft,sale"/>
  </header>
  <sheet>
    <div class="oe_button_box" name="button_box">
      <button name="open_x" type="object"><field name="x_count"/></button>
    </div>
    <div class="oe_title"><h1><field name="name"/></h1></div>
    <group>
      <group string="Customer">
        <field name="partner_id"/>
        <field name="company_id" invisible="1"/>
      </group>
    </group>
    <notebook>
      <page string="Lines" name="lines">
        <field name="order_line">
          <list><field name="product_id"/></list>
        </field>
      </page>
    </notebook>
  </sheet>
  <chatter/>
</form>''';
    final form = parseFormArch(arch);
    expect(form.buttons.map((b) => b.name), ['action_confirm', '%(42)d']);
    expect(form.buttons.first.primary, isTrue);
    expect(form.statusBar?.name, 'state');
    expect(form.canDelete, isFalse);
    expect(form.canEdit, isTrue);
    expect(form.fieldNames, containsAll(['state', 'name', 'partner_id', 'company_id', 'order_line']));
    expect(form.fieldNames, isNot(contains('product_id')));
    expect(form.fieldNames, isNot(contains('x_count')));

    final title = form.body.whereType<FormFieldNode>().single;
    expect(title.field.name, 'name');
    expect(title.isTitle, isTrue);

    final groups = form.body.whereType<FormGroupNode>().toList();
    expect(groups, hasLength(2));
    final customer = groups[0].children.single as FormGroupNode;
    expect(customer.title, 'Customer');
    expect((customer.children.single as FormFieldNode).field.name, 'partner_id');
    expect(groups[1].isPage, isTrue);
    expect(groups[1].title, 'Lines');
  });

  test('parseFormArch applies wrapper invisibility and skips warning banners', () {
    const arch = '''
<form>
  <sheet>
    <div class="alert alert-warning" invisible="not same_vat_partner_id">
      A partner with the same <span><field name="vat_label"/></span> already exists
      (<field name="same_vat_partner_id"/>).
    </div>
    <group>
      <group>
        <span class="o_form_label o_td_label" invisible="is_company">
          <field name="company_registry_label" nolabel="1"/>
        </span>
        <div invisible="not is_company">
          <field name="company_registry"/>
        </div>
        <field name="vat" invisible="parent_id and not is_company"/>
      </group>
    </group>
  </sheet>
</form>''';
    final form = parseFormArch(arch);
    // Banner helpers are still read (for modifiers) but never rendered.
    expect(form.fieldNames, containsAll(['vat_label', 'same_vat_partner_id']));
    List<FormFieldNode> fields(List<FormNode> nodes) => [
          for (final n in nodes)
            if (n is FormFieldNode) n else if (n is FormGroupNode) ...fields(n.children),
        ];
    final byName = {for (final f in fields(form.body)) f.field.name: f.field.attrs['invisible']};
    expect(byName.keys, ['company_registry_label', 'company_registry', 'vat']);
    expect(byName['company_registry_label'], 'is_company');
    expect(byName['company_registry'], 'not is_company');
    expect(byName['vat'], 'parent_id and not is_company');
  });
}
