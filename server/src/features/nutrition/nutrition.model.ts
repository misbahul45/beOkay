import { Prisma } from "../../generated/prisma/client.ts";

export const nutrients = ["calories","carbohydrates","protein","fat","fiber"] as const;
type Nutrient = typeof nutrients[number];
type Values = Partial<Record<Nutrient, number | null>>;
export function calculateNutrition(per100g: Values, grams: number | null): Record<Nutrient,number|null> {
  return Object.fromEntries(nutrients.map(key=>[key,grams===null || per100g[key]==null ? null : new Prisma.Decimal(per100g[key]!).mul(grams).div(100).toDecimalPlaces(4).toNumber()])) as Record<Nutrient,number|null>;
}
export function totalNutrition(items:Values[]) {
  return Object.fromEntries(nutrients.map(key=>{
    const known=items.filter(item=>item[key]!=null);
    return [key,{value:known.length ? known.reduce((sum,item)=>sum.add(item[key]!),new Prisma.Decimal(0)).toDecimalPlaces(4).toNumber():null,knownItems:known.length,totalItems:items.length,coverage:known.length===0?"UNKNOWN":known.length===items.length?"COMPLETE":"PARTIAL"}];
  })) as Record<Nutrient,{value:number|null;knownItems:number;totalItems:number;coverage:string}>;
}
export function numericNutrients(row:Record<Nutrient,Prisma.Decimal|null>):Record<Nutrient,number|null> {
  return Object.fromEntries(nutrients.map(key=>[key,row[key]?.toNumber()??null])) as Record<Nutrient,number|null>;
}
